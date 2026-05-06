# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Create folder on Desktop
$desktop = [Environment]::GetFolderPath("Desktop")
$folderName = "Laptop_Info_" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
$folderPath = Join-Path $desktop $folderName

New-Item -ItemType Directory -Path $folderPath | Out-Null

# Collect System Info
$system = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor
$ramGB = [math]::Round($system.TotalPhysicalMemory / 1GB)
$gpu = Get-CimInstance Win32_VideoController
$os = Get-CimInstance Win32_OperatingSystem
$disks = Get-PhysicalDisk

# Save Main Info
$mainInfo = @"
===== Laptop Details =====

Brand: $($system.Manufacturer)
Model: $($system.Model)

CPU: $($cpu.Name)
RAM: $ramGB GB

Graphics: $($gpu.Name)

OS: $($os.Caption)
"@

$mainInfo | Out-File "$folderPath\Main_Info.txt"

# Save Storage Info
$storageInfo = "===== Storage =====`n"
foreach ($disk in $disks) {
    $sizeGB = [math]::Round($disk.Size / 1GB)
    $storageInfo += "$($disk.FriendlyName) - $sizeGB GB`n"
}
$storageInfo | Out-File "$folderPath\Storage.txt"

# Save Detailed Hardware Info
Get-CimInstance Win32_ComputerSystem | Out-File "$folderPath\ComputerSystem.txt"
Get-CimInstance Win32_Processor | Out-File "$folderPath\CPU.txt"
Get-CimInstance Win32_VideoController | Out-File "$folderPath\GPU.txt"

# Battery Report
powercfg /batteryreport /output "$folderPath\Battery_Report.html"

# Full System Report
msinfo32 /report "$folderPath\Full_System_Report.txt"

Write-Output "✅ Laptop info saved to: $folderPath"
