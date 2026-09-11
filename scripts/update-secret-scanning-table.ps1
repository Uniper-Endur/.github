$ErrorActionPreference = "Stop"

$Org = $env:GITHUB_ORG

if ([string]::IsNullOrWhiteSpace($Org)) {
    throw "GITHUB_ORG environment variable is not set."
}

Write-Host "Organization: $Org"

# ============================================================
# Authentication
# ============================================================

Write-Host ""
Write-Host "Checking GitHub authentication..."

gh auth status --hostname github.com

if ($LASTEXITCODE -ne 0) {
    throw "GitHub authentication failed."
}

# ============================================================
# Generic Secret Types
# ============================================================
#
# GitHub API returns Default secret patterns by default.
# Generic patterns must be explicitly requested.
#
# These are the currently supported Generic patterns plus
# the AI-detected password pattern.
#
# ============================================================

$GenericSecretTypes = @(
    "ec_private_key",
    "generic_private_key",
    "http_basic_authentication_header",
    "http_bearer_authentication_header",
    "mongodb_connection_string",
    "mysql_connection_url",
    "openssh_private_key",
    "pgp_private_key",
    "postgres_connection_string",
    "rsa_private_key",
    "password"
)

$GenericSecretTypeParameter = $GenericSecretTypes -join ","

Write-Host ""
Write-Host "Generic secret types:"
Write-Host $GenericSecretTypeParameter

# ============================================================
# Get repositories
# ============================================================

Write-Host ""
Write-Host "Getting repositories..."

$reposJson = gh api `
    "orgs/$Org/repos?per_page=100&type=all" `
    --paginate

if ($LASTEXITCODE -ne 0) {
    throw "Unable to retrieve repositories."
}

$repos = $reposJson | ConvertFrom-Json | Where-Object { $_.name -ne ".github" }


Write-Host "Repositories found: $(@($repos).Count)"

# ============================================================
# Results
# ============================================================

$results = @()

foreach ($repo in $repos) {

    $repoName = $repo.name

    Write-Host ""
    Write-Host "========================================"
    Write-Host "Processing: $repoName"
    Write-Host "========================================"

    $defaultCount = 0
    $genericCount = 0

    # ========================================================
    # DEFAULT SECRET SCANNING
    # ========================================================

    Write-Host "Getting Default secret scanning alerts..."

    try {

        $defaultJson = gh api `
            "repos/$Org/$repoName/secret-scanning/alerts?state=open&per_page=100" `
            --paginate `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2026-03-10" `
            2>$null

        if ($LASTEXITCODE -eq 0 -and $defaultJson) {

            $defaultAlerts = $defaultJson | ConvertFrom-Json

            $defaultCount = @($defaultAlerts).Count
        }
        else {

            Write-Host "Default Secret Scanning unavailable."
        }

    }
    catch {

        Write-Host "Unable to retrieve Default alerts."
    }
    finally {

        if ($LASTEXITCODE -ne 0) {
            $global:LASTEXITCODE = 0
        }
    }

    # ========================================================
    # GENERIC SECRET SCANNING
    # ========================================================

    Write-Host "Getting Generic secret scanning alerts..."

    try {

        $genericUrl =
            "repos/$Org/$repoName/secret-scanning/alerts" +
            "?state=open" +
            "&secret_type=$GenericSecretTypeParameter" +
            "&per_page=100"

        $genericJson = gh api `
            $genericUrl `
            --paginate `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2026-03-10" `
            2>$null

        if ($LASTEXITCODE -eq 0 -and $genericJson) {

            $genericAlerts = $genericJson | ConvertFrom-Json

            $genericCount = @($genericAlerts).Count
        }
        else {

            Write-Host "Generic Secret Scanning unavailable."
        }

    }
    catch {

        Write-Host "Unable to retrieve Generic alerts."
    }
    finally {

        if ($LASTEXITCODE -ne 0) {
            $global:LASTEXITCODE = 0
        }
    }

    # ========================================================
    # Total
    # ========================================================

    $total = $defaultCount + $genericCount

    Write-Host ""
    Write-Host "Default : $defaultCount"
    Write-Host "Generic : $genericCount"
    Write-Host "Total   : $total"

    $results += [PSCustomObject]@{
        Repository = $repoName
        Default    = $defaultCount
        Generic    = $genericCount
        Total      = $total
    }
}

# ============================================================
# Organization totals
# ============================================================

$totalDefault = ($results | Measure-Object Default -Sum).Sum
$totalGeneric = ($results | Measure-Object Generic -Sum).Sum
$totalAll     = ($results | Measure-Object Total -Sum).Sum

if ($null -eq $totalDefault) {
    $totalDefault = 0
}

if ($null -eq $totalGeneric) {
    $totalGeneric = 0
}

if ($null -eq $totalAll) {
    $totalAll = 0
}

# ============================================================
# Build Markdown
# ============================================================

$table = @()

$table += "## Secret Scanning"
$table += ""
$table += "<!-- SECRET-SCANNING-START -->"
$table += ""
$table += "| Repository | Default | Generic | Total |"
$table += "|---|---:|---:|---:|"

foreach ($item in $results | Sort-Object Repository) {

    $table += "| $($item.Repository) | $($item.Default) | $($item.Generic) | $($item.Total) |"
}

$table += "| **Organization Total** | **$totalDefault** | **$totalGeneric** | **$totalAll** |"

$table += ""
$table += "<!-- SECRET-SCANNING-END -->"

$newTable = $table -join "`n"

# ============================================================
# README
# ============================================================

$readmePath = "profile/README.md"

if (-not (Test-Path $readmePath)) {
    throw "README not found: $readmePath"
}

$readme = Get-Content $readmePath -Raw

$startMarker = "<!-- SECRET-SCANNING-START -->"
$endMarker   = "<!-- SECRET-SCANNING-END -->"

# ============================================================
# Replace existing table
# ============================================================

if (
    $readme.Contains($startMarker) -and
    $readme.Contains($endMarker)
) {

    $pattern = "(?s)<!-- SECRET-SCANNING-START -->.*?<!-- SECRET-SCANNING-END -->"

    $readme = [regex]::Replace(
        $readme,
        $pattern,
        $newTable
    )

    Write-Host ""
    Write-Host "Secret Scanning table updated."

}
else {

    $readme = $readme.TrimEnd() +
        "`n`n" +
        $newTable +
        "`n"

    Write-Host ""
    Write-Host "Secret Scanning table added."
}

# ============================================================
# Save README
# ============================================================

Set-Content `
    -Path $readmePath `
    -Value $readme `
    -Encoding UTF8

# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host "========================================"
Write-Host "Secret Scanning Summary"
Write-Host "========================================"
Write-Host "Default : $totalDefault"
Write-Host "Generic : $totalGeneric"
Write-Host "Total   : $totalAll"
Write-Host "========================================"
