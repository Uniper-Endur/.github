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
$RepoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$ReadmePath = Join-Path $RepoRoot "profile/README.md"

$StartMarker = "<!-- REPO_TABLE_START -->"
$EndMarker   = "<!-- REPO_TABLE_END -->"

function Get-GitHubPagedItems {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    $json = gh api --paginate --slurp $Endpoint

    if ($LASTEXITCODE -ne 0) {
        throw "GitHub API request failed for endpoint: $Endpoint"
    }

    $pages = @($json | ConvertFrom-Json)
    $items = @()

    foreach ($page in $pages) {
        if ($null -eq $page) {
            continue
        }

        foreach ($item in @($page)) {
            if ($null -ne $item) {
                $items += $item
            }
        }
    }

    return @($items)
}

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

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed."
    exit 1
}

gh --version | Select-Object -First 1

# ------------------------------------------------------------
# Check authentication
# ------------------------------------------------------------

Write-Host "Checking GitHub authentication..."

gh auth status

if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub authentication failed."
    exit 1
}

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
    $repositories = Get-GitHubPagedItems -Endpoint "/orgs/$Org/repos?per_page=100&type=all"
}
catch {
    Write-Error "Unable to retrieve repositories."
    Write-Error $_
    exit 1
}

if ($null -eq $repositories -or @($repositories).Count -eq 0) {
    Write-Error "No repositories returned from GitHub."
    exit 1
}

Write-Host "Repositories found: $($repositories.Count)"
Write-Host ""

# ------------------------------------------------------------
# Create table rows
# ------------------------------------------------------------

$tableRows = @()

foreach ($repo in $repositories) {
    $repoName = $repo.name

    Write-Host "----------------------------------------------"
    Write-Host "Processing: $repoName"

    $language = if ([string]::IsNullOrWhiteSpace($repo.language)) { "-" } else { $repo.language }
    Write-Host "Language: $language"

    try {
        $branches = Get-GitHubPagedItems -Endpoint "/repos/$Org/$repoName/branches?per_page=100"
        $branchCount = @($branches).Count
    }
    catch {
        Write-Warning "Unable to retrieve branches for $repoName"
        $branchCount = 0
    }

    Write-Host "Branches: $branchCount"

    try {
        $tags = Get-GitHubPagedItems -Endpoint "/repos/$Org/$repoName/tags?per_page=100"
        $tagCount = @($tags).Count
    }
    catch {
        Write-Warning "Unable to retrieve tags for $repoName"
        $tagCount = 0
    }

    Write-Host "Tags: $tagCount"

    try {
        $pullRequests = Get-GitHubPagedItems -Endpoint "/repos/$Org/$repoName/pulls?state=open&per_page=100"
        $openPrCount = @($pullRequests).Count
    }
    catch {
        Write-Warning "Unable to retrieve PRs for $repoName"
        $openPrCount = 0
    }

    Write-Host "Open PRs: $openPrCount"

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

$originalReadme = Get-Content -Path $ReadmePath -Raw
$updatedReadme = $originalReadme

# ------------------------------------------------------------
# Update existing table
# ------------------------------------------------------------

$escapedStart = [regex]::Escape($StartMarker)
$escapedEnd   = [regex]::Escape($EndMarker)
$pattern = "(?s)$escapedStart.*?$escapedEnd"

if ($updatedReadme -match $pattern) {
    Write-Host "Existing repository table found."
    Write-Host "Replacing table..."

    $updatedReadme = [regex]::Replace(
        $updatedReadme,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return $table
        }
    )
}
else {
    Write-Host "Repository table markers not found."
    Write-Host "Adding repository table..."

    $updatedReadme = $updatedReadme.TrimEnd()

    $updatedReadme += @"

## Repository Overview

$table

"@
}

# ------------------------------------------------------------
# Write README only when changed
# ------------------------------------------------------------

if ($updatedReadme -eq $originalReadme) {
    Write-Host ""
    Write-Host "README already up to date. No changes written."
}
else {
    Set-Content `
        -Path $ReadmePath `
        -Value $updatedReadme `
        -Encoding UTF8

    Write-Host ""
    Write-Host "README updated on disk."
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

Write-Host ""
Write-Host "=============================================="
Write-Host " Repository Table Update Complete"
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
