$ErrorActionPreference = "Stop"

$Org = $env:GITHUB_ORG

Write-Host "Getting repositories for organization: $Org"

$repos = gh api `
    --paginate `
    "/orgs/$Org/repos?per_page=100&type=all" |
    ConvertFrom-Json

$tableRows = @()

foreach ($repo in $repos) {

    Write-Host "Processing $($repo.name)..."

    # Repository language
    $language = if ($repo.language) {
        $repo.language
    }
    else {
        "-"
    }

    # Branch count
    $branches = gh api `
        --paginate `
        "/repos/$Org/$($repo.name)/branches?per_page=100" |
        ConvertFrom-Json

    $branchCount = @($branches).Count

    # Tag count
    $tags = gh api `
        --paginate `
        "/repos/$Org/$($repo.name)/tags?per_page=100" |
        ConvertFrom-Json

    $tagCount = @($tags).Count

    # Open PR count
    $prs = gh api `
        "/repos/$Org/$($repo.name)/pulls?state=open&per_page=100" |
        ConvertFrom-Json

    $prCount = @($prs).Count

    $tableRows += "| $($repo.name) | $language | $branchCount | $tagCount | $prCount |"
}

# Sort repository names
$tableRows = $tableRows | Sort-Object

$startMarker = "<!-- REPO_TABLE_START -->"
$endMarker   = "<!-- REPO_TABLE_END -->"

$table = @"
$startMarker

| Repository | Language | Branches | Tags | Open PRs |
|------------|----------|----------|------|----------|
$($tableRows -join "`n")

$endMarker
"@

$readmePath = "README.md"

if (-not (Test-Path $readmePath)) {
    Write-Error "README.md not found."
    exit 1
}

$readme = Get-Content $readmePath -Raw

$pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"

if ($readme -match $pattern) {

    Write-Host "Updating existing repository table..."

    $readme = [regex]::Replace(
        $readme,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $table
        }
    )

}
else {

    Write-Host "Repository table markers not found. Adding table..."

    $readme += "`n`n## Repository Overview`n`n$table`n"
}

Set-Content -Path $readmePath -Value $readme -Encoding UTF8

Write-Host "Repository table updated successfully."
