# Author: Aaqil Ilyas
# Description: This script finds all symbolic links that point to a specific config directory
# Created: April 29, 2025

param(
    [Parameter(Mandatory = $false)]
    [string]$TargetPath = "$env:USERPROFILE\Documents\GitHub\.config",

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "$env:USERPROFILE\Documents\GitHub\.config\scripts\symlinks\SymbolicLink.txt",

    [Parameter(Mandatory = $false)]
    [switch]$SkipRemovableDrives,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludePaths = @("C:\Windows\System32", "C:\Windows\SysWOW64", "$env:ProgramData\Microsoft")
)

# Function to check if a path should be excluded
function ShouldExcludePath {
    param([string]$Path)

    foreach ($excludePath in $ExcludePaths) {
        if ($Path -like "$excludePath*") {
            return $true
        }
    }
    return $false
}

# Function to check if a target matches our search criteria
function TargetMatches {
    param([string[]]$Target)

    foreach ($t in $Target) {
        if ($t -eq $TargetPath -or $t -like "$TargetPath\*") {
            return $true
        }
    }
    return $false
}

# Start time for performance tracking
$startTime = Get-Date

# Display script execution details
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Find Symbolic Links" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Target path: $TargetPath" -ForegroundColor Yellow
Write-Host "Output file: $OutputFile" -ForegroundColor Yellow
Write-Host "Started at:  $startTime" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# Get all drives
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
    # Filter out removable drives if specified
    -not $SkipRemovableDrives -or (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($_.Root.Substring(0,2))'" | Select-Object -ExpandProperty DriveType) -ne 2
} | Select-Object -ExpandProperty Root

Write-Host "Scanning drives: $($drives -join ', ')" -ForegroundColor Green

# Initialize results array
$results = @()
$totalDrives = $drives.Count
$currentDrive = 0
$symlinksFound = 0

# Create an array to store errors for later review
$errors = @()

foreach ($drive in $drives) {
    $currentDrive++
    $percentComplete = ($currentDrive / $totalDrives) * 100
    $driveStartTime = Get-Date

    Write-Progress -Activity "Searching for symbolic links" -Status "Drive $currentDrive of $totalDrives : $drive" -PercentComplete $percentComplete -Id 1
    Write-Host "Scanning drive $drive... " -NoNewline -ForegroundColor Cyan

    try {
        # Get top-level folders first (increases performance and provides better progress reporting)
        $folders = @(Get-ChildItem -Path $drive -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { -not (ShouldExcludePath $_.FullName) })

        $totalFolders = $folders.Count
        $currentFolder = 0
        $driveLinkCount = 0

        Write-Host "$totalFolders folders found." -ForegroundColor Gray

        foreach ($folder in $folders) {
            $currentFolder++
            $folderPercentComplete = ($currentFolder / $totalFolders) * 100
            $folderPath = $folder.FullName

            # Skip excluded paths
            if (ShouldExcludePath $folderPath) {
                continue
            }

            Write-Progress -Activity "Scanning folders in $drive" -Status "($currentFolder of $totalFolders) $folderPath" -PercentComplete $folderPercentComplete -Id 2 -ParentId 1

            # Search for symbolic links in this folder
            try {
                $links = Get-ChildItem -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue -Directory:$false |
                Where-Object { $_.LinkType -eq 'SymbolicLink' -and (TargetMatches $_.Target) }

                if ($links.Count -gt 0) {
                    $results += $links | ForEach-Object {
                        $symlinksFound++
                        $driveLinkCount++
                        "$($_.FullName) -> $($_.Target -join ', ')"
                    }
                }
            }
            catch {
                $errorMsg = "Error processing $folderPath`: $_"
                $errors += $errorMsg
                Write-Debug $errorMsg
            }
        }

        $driveEndTime = Get-Date
        $driveElapsed = $driveEndTime - $driveStartTime
        Write-Host "Found $driveLinkCount links. Time: $($driveElapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green
    }
    catch {
        $errorMsg = "Error scanning drive $drive`: $_"
        $errors += $errorMsg
        Write-Host $errorMsg -ForegroundColor Red
    }
}

# Complete progress bars
Write-Progress -Activity "Searching for symbolic links" -Status "Complete" -Completed -Id 1
Write-Progress -Activity "Scanning folders" -Status "Complete" -Completed -Id 2

# Write results to file
if ($results.Count -gt 0) {
    $results | Set-Content -Path $OutputFile
    Write-Host "Results written to: $OutputFile" -ForegroundColor Green
}
else {
    "No symbolic links found pointing to $TargetPath" | Set-Content -Path $OutputFile
    Write-Host "No symbolic links found pointing to target path." -ForegroundColor Yellow
}

# Write errors to file if any occurred
if ($errors.Count -gt 0) {
    $errorFile = [System.IO.Path]::ChangeExtension($OutputFile, ".errors.txt")
    $errors | Set-Content -Path $errorFile
    Write-Host "Errors encountered: $($errors.Count). See: $errorFile" -ForegroundColor Yellow
}

# Calculate and display elapsed time
$endTime = Get-Date
$elapsedTime = $endTime - $startTime

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Search complete!" -ForegroundColor Green
Write-Host "Found $symlinksFound symbolic links pointing to '$TargetPath'" -ForegroundColor Green
Write-Host "Total time elapsed: $($elapsedTime.ToString('hh\:mm\:ss'))" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# Return the count for use in pipeline
return $symlinksFound
