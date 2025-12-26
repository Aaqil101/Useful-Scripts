param(
    [Parameter(Mandatory=$true)]
    [string[]]$Paths,
    [switch]$UpdateToSSH,
    [switch]$DryRun
)

$changed = 0
$totalRepos = 0

foreach ($path in $Paths) {
    $fullPath = (Resolve-Path $path).Path
    Write-Host "`nScanning: $fullPath" -ForegroundColor Magenta

    $repos = Get-ChildItem -Directory -Path $fullPath |
      Where-Object { Test-Path "$($_.FullName)\.git" }

    if ($repos.Count -eq 0) {
        Write-Host "  No Git repositories found here." -ForegroundColor DarkYellow
        continue
    }

    $totalRepos += $repos.Count
    $index = 0

    foreach ($repo in $repos) {
        $index++
        $old = git -C $repo.FullName remote get-url origin 2>$null

        if (-not $old) {
            continue
        }

        Write-Host "`n[$index] $($repo.Name)" -ForegroundColor Cyan
        Write-Host "  $old"

        if ($UpdateToSSH -and $old -match '^https://github.com/') {
            $new = $old -replace '^https://github.com/', 'git@github.com:'
            Write-Host "  -> $new" -ForegroundColor Yellow

            if (-not $DryRun) {
                git -C $repo.FullName remote set-url origin $new
                $changed++
            }
        }
    }
}

Write-Host "`n----------------------------------------" -ForegroundColor Gray
Write-Host "Total repositories found: $totalRepos" -ForegroundColor Green

if ($UpdateToSSH) {
    if ($DryRun) {
        Write-Host "Dry run complete – no changes were made." -ForegroundColor Yellow
    } else {
        Write-Host "Updated $changed repositories to SSH." -ForegroundColor Green
    }
}
