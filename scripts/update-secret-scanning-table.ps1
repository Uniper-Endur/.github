$ErrorActionPreference = "Stop"

$Org = $env:GITHUB_ORG

if ([string]::IsNullOrWhiteSpace($Org)) {
    throw "GITHUB_ORG environment variable is not set."
}

Write-Host "Organization: $Org"

# ------------------------------------------------------------
# Authentication
# ------------------------------------------------------------

Write-Host "Checking GitHub authentication..."

gh auth status --hostname github.com

if ($LASTEXITCODE -ne 0) {
    throw "GitHub authentication failed."
}

# ------------------------------------------------------------
# Get repositories
# ------------------------------------------------------------

Write-Host "Getting repositories..."

$reposJson = gh api `
    "orgs/$Org/repos?per_page=100&type=all" `
    --paginate

if ($LASTEXITCODE -ne 0) {
    throw "Unable to retrieve repositories."
}

$repos = $reposJson | ConvertFrom-Json

Write-Host "Repositories found: $(@($repos).Count)"

# ------------------------------------------------------------
# Results
# ------------------------------------------------------------

$results = @()

foreach ($repo in $repos) {

    $repoName = $repo.name

    Write-Host ""
    Write-Host "Processing: $repoName"

    $secretCount = 0

    try {

        # ----------------------------------------------------
        # Get open Secret Scanning alerts
        # ----------------------------------------------------

        $alertsJson = gh api `
            "repos/$Org/$repoName/secret-scanning/alerts?state=open&per_page=100" `
            --paginate 2>$null

        if ($LASTEXITCODE -eq 0 -and $alertsJson) {

            $alerts = $alertsJson | ConvertFrom-Json

            $secretCount = @($alerts).Count

        }
        else {

            Write-Host "  Secret Scanning unavailable or not enabled."
        }
    }
    catch {

        Write-Host "  Unable to read Secret Scanning alerts."
    }
    finally {
        if ($LASTEXITCODE -ne 0) {
            $global:LASTEXITCODE = 0
        }
    }

    Write-Host "  Open Secrets: $secretCount"

    $results += [PSCustomObject]@{
        Repository = $repoName
        Secrets    = $secretCount
    }
}

# ------------------------------------------------------------
# Organization total
# ------------------------------------------------------------

$totalSecrets = ($results | Measure-Object Secrets -Sum).Sum

if ($null -eq $totalSecrets) {
    $totalSecrets = 0
}

# ------------------------------------------------------------
# Build Markdown table
# ------------------------------------------------------------

$table = @()

$table += "## Secret Scanning"
$table += ""
$table += "<!-- SECRET-SCANNING-START -->"
$table += ""
$table += "| Repository | Open Secrets |"
$table += "|---|---:|"

foreach ($item in $results | Sort-Object Repository) {

    $table += "| $($item.Repository) | $($item.Secrets) |"
}

$table += "| **Organization Total** | **$totalSecrets** |"

$table += ""
$table += "<!-- SECRET-SCANNING-END -->"

$newTable = $table -join "`n"

# ------------------------------------------------------------
# README
# ------------------------------------------------------------

$readmePath = "profile/README.md"

if (-not (Test-Path $readmePath)) {
    throw "README not found: $readmePath"
}

$readme = Get-Content $readmePath -Raw

$startMarker = "<!-- SECRET-SCANNING-START -->"
$endMarker   = "<!-- SECRET-SCANNING-END -->"

# ------------------------------------------------------------
# Update existing table
# ------------------------------------------------------------

if ($readme.Contains($startMarker) -and
    $readme.Contains($endMarker)) {

    $pattern = "(?s)<!-- SECRET-SCANNING-START -->.*?<!-- SECRET-SCANNING-END -->"

    $readme = [regex]::Replace(
        $readme,
        $pattern,
        $newTable
    )

    Write-Host "Secret Scanning table updated."
}
else {

    $readme = $readme.TrimEnd() +
        "`n`n" +
        $newTable +
        "`n"

    Write-Host "Secret Scanning table added."
}

# ------------------------------------------------------------
# Write README
# ------------------------------------------------------------

Set-Content `
    -Path $readmePath `
    -Value $readme `
    -Encoding UTF8

Write-Host ""
Write-Host "Secret Scanning update completed."
Write-Host "Organization Total: $totalSecrets"
