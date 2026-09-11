# ============================================================
# update-repo-table.ps1
#
# Purpose:
#   Automatically update profile/README.md with GitHub
#   organization repository information.
#
# Columns:
#   Repository | Language | Branches | Tags | Open PRs
#
# Required environment variables:
#   GITHUB_ORG
#   GH_TOKEN
# ============================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$Org = $env:GITHUB_ORG

$ReadmePath = "profile/README.md"

$StartMarker = "<!-- REPO_TABLE_START -->"
$EndMarker   = "<!-- REPO_TABLE_END -->"

# ------------------------------------------------------------
# Validate environment
# ------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Org)) {
    Write-Error "GITHUB_ORG environment variable is not set."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    Write-Error "GH_TOKEN environment variable is not set."
    exit 1
}

Write-Host "=============================================="
Write-Host " GitHub Repository Table Update"
Write-Host "=============================================="
Write-Host "Organization : $Org"
Write-Host "README       : $ReadmePath"
Write-Host ""

# ------------------------------------------------------------
# Check GitHub CLI
# ------------------------------------------------------------

try {
    gh --version
}
catch {
    Write-Error "GitHub CLI (gh) is not installed."
    exit 1
}

# ------------------------------------------------------------
# Check authentication
# ------------------------------------------------------------

Write-Host "Checking GitHub authentication..."

$viewerJson = gh api "/user"

if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub authentication failed."
    exit 1
}

try {
    $viewer = $viewerJson | ConvertFrom-Json
}
catch {
    Write-Error "Unable to read authenticated GitHub user information."
    Write-Error $_
    exit 1
}

Write-Host "Authenticated as: $($viewer.login) [$($viewer.type)]"
Write-Host "Authentication successful."
Write-Host ""

# ------------------------------------------------------------
# Check README
# ------------------------------------------------------------

if (-not (Test-Path $ReadmePath)) {
    Write-Error "README file not found: $ReadmePath"
    exit 1
}

# ------------------------------------------------------------
# Get repositories
# ------------------------------------------------------------

Write-Host "Getting repositories from organization..."

try {

    $repoJson = gh api `
        --paginate `
        "/orgs/$Org/repos?per_page=100&type=all"

    if ($LASTEXITCODE -ne 0) {
        throw "GitHub API request failed."
    }

    $repositories = $repoJson | ConvertFrom-Json

}
catch {

    Write-Error "Unable to retrieve repositories."
    Write-Error $_
    exit 1
}

if ($null -eq $repositories) {
    Write-Error "No repositories returned from GitHub."
    exit 1
}

$repositories = @($repositories)

$visibilityCounts = $repositories |
    Group-Object -Property {
        if ([string]::IsNullOrWhiteSpace($_.visibility)) {
            "unknown"
        }
        else {
            $_.visibility
        }
    } |
    Sort-Object Name

$visibilitySummary = if ($visibilityCounts) {
    ($visibilityCounts | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ", "
}
else {
    "none"
}

$internalRepoCount = @(
    $repositories | Where-Object { $_.visibility -eq "internal" }
).Count

$privateRepoCount = @(
    $repositories | Where-Object { $_.private -eq $true }
).Count

Write-Host "Repositories found: $($repositories.Count)"
Write-Host "Visibility counts: $visibilitySummary"
Write-Host "Private flag counts: private=$privateRepoCount, non-private=$($repositories.Count - $privateRepoCount)"

if ($internalRepoCount -eq 0) {
    Write-Warning "No internal repositories were returned by the API for the current token."
}

Write-Host ""

# ------------------------------------------------------------
# Create table rows
# ------------------------------------------------------------

$tableRows = @()

foreach ($repo in $repositories) {

    $repoName = $repo.name

    Write-Host "----------------------------------------------"
    Write-Host "Processing: $repoName"

    # --------------------------------------------------------
    # Language
    # --------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($repo.language)) {
        $language = "-"
    }
    else {
        $language = $repo.language
    }

    Write-Host "Language: $language"

    # --------------------------------------------------------
    # Branches
    # --------------------------------------------------------

    try {

        $branchJson = gh api `
            --paginate `
            "/repos/$Org/$repoName/branches?per_page=100"

        if ($LASTEXITCODE -eq 0 -and $branchJson) {

            $branches = $branchJson | ConvertFrom-Json
            $branchCount = @($branches).Count

        }
        else {

            $branchCount = 0
        }

    }
    catch {

        Write-Warning "Unable to retrieve branches for $repoName"
        $branchCount = 0
    }

    Write-Host "Branches: $branchCount"

    # --------------------------------------------------------
    # Tags
    # --------------------------------------------------------

    try {

        $tagJson = gh api `
            --paginate `
            "/repos/$Org/$repoName/tags?per_page=100"

        if ($LASTEXITCODE -eq 0 -and $tagJson) {

            $tags = $tagJson | ConvertFrom-Json
            $tagCount = @($tags).Count

        }
        else {

            $tagCount = 0
        }

    }
    catch {

        Write-Warning "Unable to retrieve tags for $repoName"
        $tagCount = 0
    }

    Write-Host "Tags: $tagCount"

    # --------------------------------------------------------
    # Open Pull Requests
    # --------------------------------------------------------

    try {

        $prJson = gh api `
            --paginate `
            "/repos/$Org/$repoName/pulls?state=open&per_page=100"

        if ($LASTEXITCODE -eq 0 -and $prJson) {

            $pullRequests = $prJson | ConvertFrom-Json
            $openPrCount = @($pullRequests).Count

        }
        else {

            $openPrCount = 0
        }

    }
    catch {

        Write-Warning "Unable to retrieve PRs for $repoName"
        $openPrCount = 0
    }

    Write-Host "Open PRs: $openPrCount"

    # --------------------------------------------------------
    # Add Markdown row
    # --------------------------------------------------------

    $tableRows += "| $repoName | $language | $branchCount | $tagCount | $openPrCount |"
}

# ------------------------------------------------------------
# Sort table
# ------------------------------------------------------------

$tableRows = $tableRows | Sort-Object

# ------------------------------------------------------------
# Build Markdown table
# ------------------------------------------------------------

$table = @"
$StartMarker

| Repository | Language | Branches | Tags | Open PRs |
|------------|----------|----------|------|----------|
$($tableRows -join "`n")

$EndMarker
"@

# ------------------------------------------------------------
# Read README
# ------------------------------------------------------------

Write-Host ""
Write-Host "Reading $ReadmePath..."

$readme = Get-Content -Path $ReadmePath -Raw

# ------------------------------------------------------------
# Update existing table
# ------------------------------------------------------------

$escapedStart = [regex]::Escape($StartMarker)
$escapedEnd   = [regex]::Escape($EndMarker)

$pattern = "(?s)$escapedStart.*?$escapedEnd"

if ($readme -match $pattern) {

    Write-Host "Existing repository table found."
    Write-Host "Replacing table..."

    $readme = [regex]::Replace(
        $readme,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return $table
        }
    )
}

# ------------------------------------------------------------
# Add table if it does not exist
# ------------------------------------------------------------

else {

    Write-Host "Repository table markers not found."
    Write-Host "Adding repository table..."

    $readme = $readme.TrimEnd()

    $readme += @"

## Repository Overview

$table

"@
}

# ------------------------------------------------------------
# Write README
# ------------------------------------------------------------

Set-Content `
    -Path $ReadmePath `
    -Value $readme `
    -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

Write-Host ""
Write-Host "=============================================="
Write-Host " Repository Table Updated Successfully"
Write-Host "=============================================="
Write-Host "Organization : $Org"
Write-Host "Repositories : $($repositories.Count)"
Write-Host "README       : $ReadmePath"
Write-Host ""
Write-Host "Updated columns:"
Write-Host "  Repository"
Write-Host "  Language"
Write-Host "  Branches"
Write-Host "  Tags"
Write-Host "  Open PRs"
Write-Host ""
Write-Host "Done."
