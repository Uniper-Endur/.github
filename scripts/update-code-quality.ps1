$ErrorActionPreference = "Stop"

$Org = $env:GITHUB_ORG

if ([string]::IsNullOrWhiteSpace($Org)) {
    throw "GITHUB_ORG environment variable is not set."
}

Write-Host "Organization: $Org"

# ============================================================
# Validate GitHub authentication
# ============================================================

Write-Host ""
Write-Host "Checking GitHub authentication..."

gh auth status --hostname github.com

if ($LASTEXITCODE -ne 0) {
    throw "GitHub authentication failed."
}

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

$repos = $reposJson |
    ConvertFrom-Json |
    Where-Object {
        $_.name -ne ".github"
    }

Write-Host "Repositories found: $(@($repos).Count)"

# ============================================================
# Prepare results
# ============================================================

$results = @()

foreach ($repo in $repos) {

    $repoName = $repo.name

    Write-Host ""
    Write-Host "Processing: $repoName"

    $status   = "Not Configured"
    $errors   = 0
    $warnings = 0

    try {

        # ----------------------------------------------------
        # Get Code Quality setup
        # ----------------------------------------------------

        $setupJson = gh api `
            "repos/$Org/$repoName/code-quality/setup" `
            2>$null

        if ($LASTEXITCODE -eq 0 -and $setupJson) {

            $setup = $setupJson | ConvertFrom-Json

            if ($setup.state -eq "configured") {

                $status = "Configured"

                Write-Host "  Code Quality: Configured"

                # ------------------------------------------------
                # Get open Code Quality findings
                # ------------------------------------------------

                $findingsJson = gh api `
                    "repos/$Org/$repoName/code-quality/findings?state=open&per_page=100" `
                    --paginate `
                    2>$null

                if ($LASTEXITCODE -eq 0 -and $findingsJson) {

                    $findings = $findingsJson | ConvertFrom-Json

                    foreach ($finding in @($findings)) {

                        $severity = $finding.rule.severity

                        if ([string]::IsNullOrWhiteSpace($severity)) {
                            continue
                        }

                        switch ($severity.ToLower()) {

                            "error" {
                                $errors++
                            }

                            "warning" {
                                $warnings++
                            }
                        }
                    }
                }
                else {
                    Write-Host "  No Code Quality findings returned."
                }
            }
            else {
                Write-Host "  Code Quality: Not Configured"
            }
        }
        else {
            Write-Host "  Code Quality setup unavailable."
        }
    }
    catch {
        Write-Host "  Unable to read Code Quality information."
    }
    finally {
        if ($LASTEXITCODE -ne 0) {
            $global:LASTEXITCODE = 0
        }
    }

    $total = $errors + $warnings

    Write-Host "  Status   : $status"
    Write-Host "  Errors   : $errors"
    Write-Host "  Warnings : $warnings"
    Write-Host "  Total    : $total"

    $results += [PSCustomObject]@{
        Repository = $repoName
        Status     = $status
        Errors     = $errors
        Warnings   = $warnings
        Total      = $total
    }
}

# ============================================================
# Calculate organization totals
# ============================================================

$totalErrors = ($results | Measure-Object Errors -Sum).Sum
$totalWarnings = ($results | Measure-Object Warnings -Sum).Sum

if ($null -eq $totalErrors) {
    $totalErrors = 0
}

if ($null -eq $totalWarnings) {
    $totalWarnings = 0
}

$totalAll = $totalErrors + $totalWarnings

$configuredCount = @(
    $results | Where-Object {
        $_.Status -eq "Configured"
    }
).Count

$notConfiguredCount = @(
    $results | Where-Object {
        $_.Status -eq "Not Configured"
    }
).Count

# ============================================================
# Build Markdown table
# ============================================================

$table = @()


$table += ""
$table += "| Repository | ⚙️ Status | 🔴 Errors | 🟠 Warnings | 🔵 Total |"
$table += "|---|---|---:|---:|---:|"

foreach ($item in $results | Sort-Object Repository) {

    $table += "| $($item.Repository) | $($item.Status) | $($item.Errors) | $($item.Warnings) | $($item.Total) |"
}

$table += "| **Organization Total** | **Configured: $configuredCount** | **$totalErrors** | **$totalWarnings** | **$totalAll** |"

$table += ""
$table += "<!-- CODE-QUALITY-END -->"

$newTable = $table -join "`n"

# ============================================================
# README
# ============================================================

$readmePath = "profile/README.md"

if (-not (Test-Path $readmePath)) {
    throw "README not found: $readmePath"
}

$readme = Get-Content $readmePath -Raw

$startMarker = "<!-- CODE-QUALITY-START -->"
$endMarker   = "<!-- CODE-QUALITY-END -->"

# ============================================================
# Replace existing table
# ============================================================

if ($readme.Contains($startMarker) -and
    $readme.Contains($endMarker)) {

    $pattern = "(?s)<!-- CODE-QUALITY-START -->.*?<!-- CODE-QUALITY-END -->"

    $readme = [regex]::Replace(
        $readme,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $newTable
        }
    )

    Write-Host "Code Quality table updated."
}
else {

    $readme = $readme.TrimEnd() +
        "`n`n" +
        $newTable +
        "`n"

    Write-Host "Code Quality table added."
}

# ============================================================
# Write README
# ============================================================

Set-Content `
    -Path $readmePath `
    -Value $readme `
    -Encoding UTF8

# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host "============================================"
Write-Host "Code Quality update completed."
Write-Host "============================================"
Write-Host "Configured repositories    : $configuredCount"
Write-Host "Not configured repositories: $notConfiguredCount"
Write-Host "Errors                     : $totalErrors"
Write-Host "Warnings                   : $totalWarnings"
Write-Host "Total findings             : $totalAll"
Write-Host "============================================"
