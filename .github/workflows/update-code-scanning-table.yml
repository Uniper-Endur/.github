name: Update Code Scanning Table

on:
  push:
    paths:
      - 'scripts/update-code-scanning-table.ps1'
      - '.github/workflows/update-code-scanning-table.yml'
  workflow_dispatch:
  schedule:
    - cron: '0 6 * * *'

permissions:
  contents: write
  security-events: read

jobs:
  update-code-scanning-table:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Test GH_TOKEN
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
        run: |
          if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
              throw "Token is EMPTY"
          }

          Write-Host "Token is present. Length: $($env:GH_TOKEN.Length)"

          gh auth status --hostname github.com

          if ($LASTEXITCODE -ne 0) {
              throw "GitHub authentication failed."
          }

      - name: Update Code Scanning table
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
          GITHUB_ORG: "Uniper-Endur"
        run: |
          ./scripts/update-code-scanning-table.ps1

      - name: Commit README changes
        shell: bash
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          git add profile/README.md

          if git diff --cached --quiet; then
            echo "No changes to commit."
          else
            git commit -m "chore: update code scanning table"
            git push
          fi
