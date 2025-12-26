# Author: Aaqil Ilyas
# Description: This script creates symbolic links for vscode-workspaces
# Created: May 21, 2025

param(
    [Parameter(Mandatory = $false)]
    [string]$VscodeWorkspaces = "$env:USERPROFILE\Documents\GitHub",

    [Parameter(Mandatory = $false)]
    [switch]$ForceRecreate,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$CreateDirectories
)

# Display script execution details
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Create Symbolic Links" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Vscode Workspaces path: $VscodeWorkspaces" -ForegroundColor Yellow
Write-Host "Force recreate: $ForceRecreate" -ForegroundColor Yellow
Write-Host "What-if mode: $WhatIf" -ForegroundColor Yellow
Write-Host "Create parent directories: $CreateDirectories" -ForegroundColor Yellow
Write-Host "Started at: $(Get-Date)" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# Function to create parent directories if they don't exist
function EnsureParentDirectoryExists {
    param([string]$Path)

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $directory)) {
        if ($CreateDirectories) {
            Write-Host "Creating parent directory: $directory" -ForegroundColor Gray
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            return $true
        }
        else {
            Write-Warning "Parent directory does not exist: $directory. Use -CreateDirectories to create it."
            return $false
        }
    }
    return $true
}

# Each entry is [LinkPath, TargetPath]
$symlinks = @(
    @("C:\.config", "$VscodeWorkspaces\.config"),
    @("C:\Expansion", "$VscodeWorkspaces\Expansion"),
    @("C:\Obsidian", "$VscodeWorkspaces\Obsidian"),
    @("C:\Post-Library", "$VscodeWorkspaces\Post-Library"),
    @("C:\AutoHotkey-Scripts", "$VscodeWorkspaces\AutoHotkey-Scripts"),
    @("C:\Startup-Shutdown", "$VscodeWorkspaces\Startup-Shutdown"),
    @("C:\TimeSlice", "$VscodeWorkspaces\TimeSlice"),
    @("C:\toggl-to-timekeep", "$VscodeWorkspaces\toggl-to-timekeep")
)

# Initialize counters
$successful = 0
$skipped = 0
$failed = 0
$total = $symlinks.Count

Write-Host "Found $total symlinks to process." -ForegroundColor Green

# Process each symlink
foreach ($link in $symlinks) {
    $linkPath = $link[0]
    $targetPath = $link[1]

    Write-Host "`nProcessing: $linkPath -> $targetPath" -ForegroundColor Cyan

    # Check if the link path already exists
    if (Test-Path -Path $linkPath) {
        # If it exists, check if it's already a symlink pointing to the correct target
        $existingItem = Get-Item -Path $linkPath -Force -ErrorAction SilentlyContinue

        if ($existingItem.LinkType -eq "SymbolicLink") {
            $existingTarget = $existingItem.Target

            if ($existingTarget -eq $targetPath) {
                Write-Host "Symlink already exists with correct target. Skipping." -ForegroundColor Yellow
                $skipped++
                continue
            }
            else {
                Write-Host "Symlink exists but points to different target: $existingTarget" -ForegroundColor Yellow

                if (-not $ForceRecreate) {
                    Write-Host "Use -ForceRecreate to overwrite. Skipping." -ForegroundColor Yellow
                    $skipped++
                    continue
                }
                else {
                    Write-Host "Force recreate enabled. Removing existing symlink." -ForegroundColor Yellow
                    if (-not $WhatIf) {
                        Remove-Item -Path $linkPath -Force
                    }
                }
            }
        }
        else {
            Write-Host "Path exists but is not a symlink. It's a $($existingItem.GetType().Name)." -ForegroundColor Yellow

            if (-not $ForceRecreate) {
                Write-Host "Use -ForceRecreate to overwrite. Skipping." -ForegroundColor Yellow
                $skipped++
                continue
            }
            else {
                Write-Host "Force recreate enabled. Removing existing item." -ForegroundColor Yellow
                if (-not $WhatIf) {
                    Remove-Item -Path $linkPath -Force -Recurse
                }
            }
        }
    }

    # Ensure the target path exists
    if (-not (Test-Path -Path $targetPath)) {
        Write-Warning "Target path does not exist: $targetPath"
        Write-Host "Note: On a new system, this may be normal if you haven't restored your config files yet." -ForegroundColor Gray
    }

    # Ensure parent directory exists
    if (-not (EnsureParentDirectoryExists -Path $linkPath)) {
        Write-Host "Skipping link creation due to missing parent directory." -ForegroundColor Red
        $failed++
        continue
    }

    # Create the symbolic link
    try {
        if ($WhatIf) {
            Write-Host "WHAT-IF: Would create symlink: $linkPath -> $targetPath" -ForegroundColor Magenta
            $successful++
        }
        else {
            Write-Host "Creating symlink: $linkPath -> $targetPath" -ForegroundColor Green
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -Force | Out-Null
            if ($?) {
                $successful++
            }
            else {
                $failed++
            }
        }
    }
    catch {
        Write-Host "Error creating symlink: $_" -ForegroundColor Red
        $failed++
    }
}

# Display summary
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Symlink Creation Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total symlinks processed: $total" -ForegroundColor Yellow
Write-Host "Successfully created: $successful" -ForegroundColor Green
Write-Host "Skipped (already exist): $skipped" -ForegroundColor Yellow
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "Completed at: $(Get-Date)" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# Return true if all links were created successfully or skipped
return ($failed -eq 0)
