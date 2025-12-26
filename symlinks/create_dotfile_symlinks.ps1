# Author: Aaqil Ilyas
# Description: This script creates symbolic links for dotfiles configuration
# Created: April 29, 2025

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\Documents\GitHub\.config",

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
Write-Host "Config path: $ConfigPath" -ForegroundColor Yellow
Write-Host "Force recreate: $ForceRecreate" -ForegroundColor Yellow
Write-Host "What-if mode: $WhatIf" -ForegroundColor Yellow
Write-Host "Create parent directories: $CreateDirectories" -ForegroundColor Yellow
Write-Host "Started at: $(Get-Date)" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# Function to create parent directories if they don't exist
function EnsureParentDirectoryExists {
    param([string]$Path)

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            Write-Error "ERROR: Path is null or empty"
            return $false
        }

        $directory = Split-Path -Path $Path -Parent

        if ([string]::IsNullOrWhiteSpace($directory)) {
            Write-Error "ERROR: Could not determine parent directory for path: $Path"
            return $false
        }

        if (-not (Test-Path -Path $directory)) {
            if ($CreateDirectories) {
                Write-Host "Creating parent directory: $directory" -ForegroundColor Gray
                if (-not $WhatIf) {
                    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
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
    catch {
        Write-Error "ERROR in EnsureParentDirectoryExists: $($_.Exception.Message)"
        return $false
    }
}

# Define all symlinks using PSCustomObject for reliability
$symlinks = @(
    [PSCustomObject]@{
        Link   = "C:\Program Files\Nilesoft Shell\imports"
        Target = "$ConfigPath\nilesoft-shell\imports"
    }
    [PSCustomObject]@{
        Link   = "C:\Program Files\Nilesoft Shell\themes"
        Target = "$ConfigPath\nilesoft-shell\themes"
    }
    [PSCustomObject]@{
        Link   = "C:\Program Files\Nilesoft Shell\shell.nss"
        Target = "$ConfigPath\nilesoft-shell\shell.nss"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.bash_profile"
        Target = "$ConfigPath\bash\.bash_profile"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.bashrc"
        Target = "$ConfigPath\bash\.bashrc"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.gitconfig"
        Target = "$ConfigPath\git\.gitconfig"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.config\fastfetch"
        Target = "$ConfigPath\fastfetch"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.config\komorebi"
        Target = "$ConfigPath\komorebi"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.config\yasb"
        Target = "$ConfigPath\yasb"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\.config\posh"
        Target = "$ConfigPath\posh"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Local\Blender Launcher\Blender Launcher.ini"
        Target = "$ConfigPath\blender-launcher\Blender Launcher.ini"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
        Target = "$ConfigPath\winget\settings.json"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        Target = "$ConfigPath\windows-terminal\settings.json"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Everything"
        Target = "$ConfigPath\everything"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Explorer-Dialog-Path-Selector"
        Target = "$ConfigPath\explorer-dialog-path-selector"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\FlowLauncher"
        Target = "$ConfigPath\flow-launcher"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Blast"
        Target = "$ConfigPath\blast"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Notepad++"
        Target = "$ConfigPath\notepad++"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\pooi.moe"
        Target = "$ConfigPath\pooi.moe"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\PureRef"
        Target = "$ConfigPath\pureref"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\qBittorrent"
        Target = "$ConfigPath\qbittorrent"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\vlc"
        Target = "$ConfigPath\vlc"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Code\User"
        Target = "$ConfigPath\code\User"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Adobe\Adobe Photoshop 2023"
        Target = "$ConfigPath\adobe-photoshop-2023"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\HandBrake"
        Target = "$ConfigPath\handbrake"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\TeraCopy"
        Target = "$ConfigPath\teracopy"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\Documents\PowerShell"
        Target = "$ConfigPath\powershell"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\Documents\WindowsPowerShell"
        Target = "$ConfigPath\windows-powershell"
    }
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Direct Folders"
        Target = "$ConfigPath\direct-folders"
    }
    [PSCustomObject]@{
        Link   = "$env:ProgramData\Windhawk"
        Target = "$ConfigPath\windhawk"
    }

    # Symlink in another location
    [PSCustomObject]@{
        Link   = "$env:USERPROFILE\AppData\Roaming\Blender Foundation\Blender"
        Target = "$env:USERPROFILE\Documents\GitHub\Blender"
    }
)

# Initialize counters
$successful = 0
$skipped = 0
$failed = 0
$total = $symlinks.Count

Write-Host "Found $total symlinks to process." -ForegroundColor Green

# Process each symlink
foreach ($link in $symlinks) {
    $linkPath = $link.Link
    $targetPath = $link.Target

    # Validate paths before processing
    if ([string]::IsNullOrWhiteSpace($linkPath)) {
        Write-Host "`n[ERROR] Link path is null or empty. Skipping this entry." -ForegroundColor Red
        Write-Host "Entry details: $($link | ConvertTo-Json -Compress)" -ForegroundColor Gray
        $failed++
        continue
    }

    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        Write-Host "`n[ERROR] Target path is null or empty for link: $linkPath" -ForegroundColor Red
        Write-Host "Entry details: $($link | ConvertTo-Json -Compress)" -ForegroundColor Gray
        $failed++
        continue
    }

    Write-Host "`n============================================================" -ForegroundColor DarkGray
    Write-Host "Processing symlink:" -ForegroundColor Cyan
    Write-Host "  Link:   $linkPath" -ForegroundColor White
    Write-Host "  Target: $targetPath" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor DarkGray

    # Check if the link path already exists
    if (Test-Path -Path $linkPath) {
        # If it exists, check if it's already a symlink pointing to the correct target
        try {
            $existingItem = Get-Item -Path $linkPath -Force -ErrorAction Stop

            if ($existingItem.LinkType -eq "SymbolicLink") {
                $existingTarget = $existingItem.Target

                if ($existingTarget -eq $targetPath) {
                    Write-Host "[SKIP] Symlink already exists with correct target." -ForegroundColor Yellow
                    $skipped++
                    continue
                }
                else {
                    Write-Host "[WARN] Symlink exists but points to: $existingTarget" -ForegroundColor Yellow

                    if (-not $ForceRecreate) {
                        Write-Host "[SKIP] Use -ForceRecreate to overwrite." -ForegroundColor Yellow
                        $skipped++
                        continue
                    }
                    else {
                        Write-Host "[INFO] Force recreate enabled. Removing existing symlink." -ForegroundColor Yellow
                        if (-not $WhatIf) {
                            Remove-Item -Path $linkPath -Force -ErrorAction Stop
                        }
                    }
                }
            }
            else {
                Write-Host "[WARN] Path exists but is not a symlink. Type: $($existingItem.GetType().Name)" -ForegroundColor Yellow

                if (-not $ForceRecreate) {
                    Write-Host "[SKIP] Use -ForceRecreate to overwrite." -ForegroundColor Yellow
                    $skipped++
                    continue
                }
                else {
                    Write-Host "[INFO] Force recreate enabled. Removing existing item." -ForegroundColor Yellow
                    if (-not $WhatIf) {
                        Remove-Item -Path $linkPath -Force -Recurse -ErrorAction Stop
                    }
                }
            }
        }
        catch {
            Write-Host "[ERROR] Failed to check existing item: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
            continue
        }
    }

    # Ensure the target path exists
    if (-not (Test-Path -Path $targetPath)) {
        Write-Host "[WARN] Target path does not exist: $targetPath" -ForegroundColor Yellow
        Write-Host "[INFO] This is normal on a new system before restoring config files." -ForegroundColor Gray
    }

    # Ensure parent directory exists
    if (-not (EnsureParentDirectoryExists -Path $linkPath)) {
        Write-Host "[FAIL] Cannot create symlink - parent directory issue." -ForegroundColor Red
        $failed++
        continue
    }

    # Create the symbolic link
    try {
        if ($WhatIf) {
            Write-Host "[WHAT-IF] Would create symlink" -ForegroundColor Magenta
            $successful++
        }
        else {
            Write-Host "[CREATE] Creating symlink..." -ForegroundColor Green
            $result = New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -Force -ErrorAction Stop

            if ($result) {
                Write-Host "[SUCCESS] Symlink created successfully!" -ForegroundColor Green
                $successful++
            }
            else {
                Write-Host "[FAIL] New-Item returned null/false" -ForegroundColor Red
                $failed++
            }
        }
    }
    catch {
        Write-Host "[ERROR] Failed to create symlink" -ForegroundColor Red
        Write-Host "  Exception: $($_.Exception.GetType().FullName)" -ForegroundColor Red
        Write-Host "  Message: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Link: $linkPath" -ForegroundColor Gray
        Write-Host "  Target: $targetPath" -ForegroundColor Gray
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
