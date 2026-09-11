$ErrorActionPreference = "Stop"

$Org = $env:GITHUB_ORG

if ([string]::IsNullOrWhiteSpace($Org)) {
    throw "GITHUB_ORG environment variable is not set."
}

Write-Host "Organization: $Org"

# ------------------------------------------------------------
# Validate GitHub authentication
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

$repos = $reposJson | ConvertFrom-Json | Where-Object { $_.name -ne ".github" }

Write-Host "Repositories found: $(@($repos).Count)"

# ------------------------------------------------------------
# Prepare results
# ------------------------------------------------------------

$results = @()

foreach ($repo in $repos) {

    $repoName = $repo.name

    Write-Host ""
    Write-Host "Processing: $repoName"

    $critical = 0
    $high     = 0
    $medium   = 0
    $low      = 0

    try {

        # ----------------------------------------------------
        # Get open Code Scanning alerts
        # ----------------------------------------------------

        $alertsJson = gh api `
            "repos/$Org/$repoName/code-scanning/alerts?state=open&per_page=100" `
            --paginate 2>$null

        if ($LASTEXITCODE -eq 0 -and $alertsJson) {

            $alerts = $alertsJson | ConvertFrom-Json

            foreach ($alert in @($alerts)) {

                $severity = $alert.rule.security_severity_level

                if ([string]::IsNullOrWhiteSpace($severity)) {
                    continue
                }

                switch ($severity.ToLower()) {

                    "critical" {
                        $critical++
                    }

                    "high" {
                        $high++
                    }

                    "medium" {
                        $medium++
                    }

                    "low" {
                        $low++
                    }
                }
            }
        }
        else {
            Write-Host "  Code Scanning unavailable or not enabled."
        }
    }
    catch {
        Write-Host "  Unable to read Code Scanning alerts."
    }
    finally {
        if ($LASTEXITCODE -ne 0) {
            $global:LASTEXITCODE = 0
        }
    }

    $total = $critical + $high + $medium + $low

    Write-Host "  Critical : $critical"
    Write-Host "  High     : $high"
    Write-Host "  Medium   : $medium"
    Write-Host "  Low      : $low"
    Write-Host "  Total    : $total"

    $results += [PSCustomObject]@{
        Repository = $repoName
        Critical   = $critical
        High       = $high
        Medium     = $medium
        Low        = $low
        Total      = $total
    }
}

# ------------------------------------------------------------
# Calculate organization totals
# ------------------------------------------------------------

$totalCritical = ($results | Measure-Object Critical -Sum).Sum
$totalHigh     = ($results | Measure-Object High -Sum).Sum
$totalMedium   = ($results | Measure-Object Medium -Sum).Sum
$totalLow      = ($results | Measure-Object Low -Sum).Sum

if ($null -eq $totalCritical) { $totalCritical = 0 }
if ($null -eq $totalHigh)     { $totalHigh = 0 }
if ($null -eq $totalMedium)   { $totalMedium = 0 }
if ($null -eq $totalLow)      { $totalLow = 0 }

$totalAll = $totalCritical + $totalHigh + $totalMedium + $totalLow

# ------------------------------------------------------------
# Build Markdown table
# ------------------------------------------------------------

$table = @()

$table += "## Code Scanning Security"
$table += ""
$table += "<!-- CODE-SCANNING-START -->"
$table += ""
$table += "| Repository | Critical | High | Medium | Low | Total |"
$table += "|---|---:|---:|---:|---:|---:|"

foreach ($item in $results | Sort-Object Repository) {

    $table += "| $($item.Repository) | $($item.Critical) | $($item.High) | $($item.Medium) | $($item.Low) | $($item.Total) |"
}

$table += "| **Organization Total** | **$totalCritical** | **$totalHigh** | **$totalMedium** | **$totalLow** | **$totalAll** |"

$table += ""
$table += "<!-- CODE-SCANNING-END -->"

$newTable = $table -join "`n"

# ------------------------------------------------------------
# README
# ------------------------------------------------------------

$readmePath = "profile/README.md"

if (-not (Test-Path $readmePath)) {
    throw "README not found: $readmePath"
}

$readme = Get-Content $readmePath -Raw

$startMarker = "<!-- CODE-SCANNING-START -->"
$endMarker   = "<!-- CODE-SCANNING-END -->"

# ------------------------------------------------------------
# Replace existing table
# ------------------------------------------------------------

if ($readme.Contains($startMarker) -and $readme.Contains($endMarker)) {

    $pattern = "(?s)<!-- CODE-SCANNING-START -->.*?<!-- CODE-SCANNING-END -->"

    $replacement = $newTable

    $readme = [regex]::Replace(
        $readme,
        $pattern,
        $replacement
    )

    Write-Host "Code Scanning table updated."

}
else {

    # If markers don't exist, append the table

    $readme = $readme.TrimEnd() +
        "`n`n" +
        $newTable +
        "`n"

    Write-Host "Code Scanning table added."
}

# ------------------------------------------------------------
# Write README
# ------------------------------------------------------------

Set-Content `
    -Path $readmePath `
    -Value $readme `
    -Encoding UTF8

Write-Host ""
Write-Host "Code Scanning table update completed."
Write-Host "Critical: $totalCritical"
Write-Host "High    : $totalHigh"
Write-Host "Medium  : $totalMedium"
Write-Host "Low     : $totalLow"
Write-Host "Total   : $totalAll"
