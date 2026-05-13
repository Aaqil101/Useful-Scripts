# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$conditionNotes = Read-Host -Prompt "Enter condition notes (scratches, accessories, missing items, etc.)"

$scriptDir = Split-Path -Parent $PSCommandPath
$desktop = [Environment]::GetFolderPath("Desktop")
$templatePath = Join-Path $scriptDir "Laptop Details Sheet Template.xlsx"
$outputName = "Laptop_Details_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').xlsx"
$outputPath = Join-Path $desktop $outputName

# --- System / Brand / Model ---
try {
    $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $brand = $system.Manufacturer
    $model = $system.Model
} catch { $brand = "N/A"; $model = "N/A"; Write-Warning "Could not retrieve system info: $_" }

# --- Serial Number ---
try {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $serial = $bios.SerialNumber
    if ($serial -match "O\.?E\.?M\.?|To be filled|System Serial|Default") { $serial = "N/A" }
} catch { $serial = "N/A" }

# --- Operating System ---
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $osInfo = "$($os.Caption) ($($os.OSArchitecture))"
} catch { $osInfo = "N/A" }

# --- Processor ---
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
    $cpuInfo = "$($cpu.Name) ($($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads)"
} catch { $cpuInfo = "N/A" }

# --- RAM ---
try {
    $totalRAM = [math]::Round($system.TotalPhysicalMemory / 1GB, 1)
    $ramSticks = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop
    $ramParts = @()
    $i = 1
    foreach ($stick in $ramSticks) {
        $cap = [math]::Round($stick.Capacity / 1GB)
        $speed = $stick.Speed
        $form = if ($stick.FormFactor -eq 12) { "SODIMM" } elseif ($stick.FormFactor -eq 8) { "DIMM" } else { "unknown" }
        $ramParts += "Slot ${i}: ${cap}GB ${speed}MHz $form"
        $i++
    }
    $ramDetailStr = $ramParts -join " | "
} catch { $totalRAM = "N/A"; $ramDetailStr = "N/A" }

# --- Storage ---
try {
    $disks = Get-PhysicalDisk -ErrorAction Stop
    $storageRows = @()
    foreach ($disk in $disks) {
        $sizeGB = [math]::Round($disk.Size / 1GB)
        $type = switch ($disk.MediaType) {
            0 { "HDD" }; 3 { "HDD" }; 4 { "SSD" }
            default { "Unknown" }
        }
        if ($disk.BusType -eq 11) { $type = "NVMe" }
        $storageRows += "$($disk.FriendlyName) -- $type -- ${sizeGB}GB"
    }
    $drive1 = if ($storageRows.Count -ge 1) { $storageRows[0] } else { "N/A" }
    $drive2 = if ($storageRows.Count -ge 2) { $storageRows[1] } else { "N/A" }
} catch { $drive1 = "N/A"; $drive2 = "N/A" }

# --- Graphics ---
try {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
    $gpuParts = @()
    foreach ($gpu in $gpus) {
        $vram = if ($gpu.AdapterRAM) { "$([math]::Round($gpu.AdapterRAM / 1GB, 1))GB" } else { "?" }
        $gpuParts += "$($gpu.Name) ($vram)"
    }
    $gpuInfo = $gpuParts -join " | "
} catch { $gpuInfo = "N/A" }

# --- Screen Resolution ---
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $resolution = "$($bounds.Width)x$($bounds.Height)"
} catch { $resolution = "N/A" }

# --- Touchscreen ---
try {
    $touch = Get-PnpDevice | Where-Object {
        $_.Class -eq "HIDClass" -and $_.Status -eq "OK" -and
        ($_.FriendlyName -match "touch|digitizer|pen|surface")
    }
    $touchscreen = if ($touch) { "Yes" } else { "No" }
} catch { $touchscreen = "N/A" }

# --- Battery ---
try {
    $batStatic = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop
    $designCap = ($batStatic | Select-Object -First 1).DesignedCapacity

    $batFull = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
    $fullCap = if ($batFull) { $batFull.FullChargedCapacity } else { "N/A" }

    $batCycle = Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | Select-Object -First 1
    $cycleCount = if ($batCycle) { $batCycle.CycleCount } else { "N/A" }

    $batChem = switch (($batStatic | Select-Object -First 1).Chemistry) {
        1 { "Li-Ion" }; 2 { "Li-Poly" }; 3 { "LiFePO4" }
        default { "Unknown" }
    }

    if ($designCap -and $fullCap -ne "N/A" -and $designCap -gt 0) {
        $healthStr = "$([math]::Round(($fullCap / $designCap) * 100, 1))%"
    } else { $healthStr = "N/A" }
} catch { $designCap = "N/A"; $fullCap = "N/A"; $cycleCount = "N/A"; $healthStr = "N/A"; $batChem = "N/A" }

# --- Wi-Fi ---
try {
    $wifi = Get-NetAdapter -Name "*Wi-Fi*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wifi) {
        $wifi = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Wireless|Wi-Fi|802\.11" } | Select-Object -First 1
    }
    $wifiInfo = if ($wifi) { "$($wifi.Name) -- $($wifi.InterfaceDescription)" } else { "N/A" }
} catch { $wifiInfo = "N/A" }

# --- Bluetooth ---
try {
    $bt = Get-PnpDevice | Where-Object { $_.Class -eq "Bluetooth" -and $_.Status -eq "OK" } | Select-Object -First 1
    $btInfo = if ($bt) { "Yes" } else { "No" }
} catch { $btInfo = "N/A" }

# --- USB Ports ---
try {
    $usbCount = (Get-CimInstance Win32_USBController -ErrorAction Stop).Count
} catch { $usbCount = "N/A" }

# --- Video Ports ---
try {
    $names = (Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -eq "OK" }).FriendlyName -join " "
    $found = @()
    if ($names -match "HDMI") { $found += "HDMI" }
    if ($names -match "DisplayPort") { $found += "DisplayPort" }
    if ($names -match "Thunderbolt") { $found += "Thunderbolt" }
    if ($names -match "VGA") { $found += "VGA" }
    if ($names -match "DVI") { $found += "DVI" }
    $videoPortStr = if ($found) { $found -join ", " } else { "Check device" }
} catch { $videoPortStr = "N/A" }

# --- Optical Drive ---
try {
    $optical = Get-CimInstance Win32_CDROMDrive -ErrorAction Stop
    $opticalInfo = if ($optical) { "Yes -- $($optical.Name)" } else { "No" }
} catch { $opticalInfo = "N/A" }

# --- Ethernet ---
try {
    $eth = Get-NetAdapter -Name "*Ethernet*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $eth) {
        $eth = Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -match "Ethernet|Realtek|Intel.*[^Wi]" -and
            $_.InterfaceDescription -notmatch "Wireless|Wi-Fi|802\.11|Virtual|Bluetooth"
        } | Select-Object -First 1
    }
    $ethInfo = if ($eth) { "$($eth.InterfaceDescription)`nMAC: $($eth.MacAddress)" } else { "N/A" }
} catch { $ethInfo = "N/A" }

# ============================================================
# Excel Output
# ============================================================

if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found at: $templatePath"
    exit 1
}

Copy-Item -Path $templatePath -Destination $outputPath -Force

$rows = @(
    @("Brand", $brand)
    @("Model", $model)
    @("Serial Number", $serial)
    @("Operating System", $osInfo)
    @("Processor", $cpuInfo)
    @("Total RAM", "${totalRAM} GB")
    @("RAM Details", $ramDetailStr)
    @("Storage Drive 1", $drive1)
    @("Storage Drive 2", $drive2)
    @("Graphics", $gpuInfo)
    @("Screen Resolution", $resolution)
    @("Touchscreen", $touchscreen)
    @("Battery Design Capacity", "$designCap mWh")
    @("Battery Full Charge Capacity", "$fullCap mWh")
    @("Battery Cycle Count", $cycleCount)
    @("Battery Health", $healthStr)
    @("Battery Chemistry", $batChem)
    @("Wi-Fi", $wifiInfo)
    @("Bluetooth", $btInfo)
    @("USB Port Count", $usbCount)
    @("Video Ports", $videoPortStr)
    @("Optical Drive", $opticalInfo)
    @("Ethernet", $ethInfo)
    @("Condition Notes", $conditionNotes)
)

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $wb = $excel.Workbooks.Open($outputPath)
    $ws = $wb.Worksheets(1)

    $ws.Cells.Item(1, 1) = "Feature"
    $ws.Cells.Item(1, 2) = "Info"

    $rowNum = 2
    foreach ($row in $rows) {
        $ws.Cells.Item($rowNum, 1) = $row[0]
        $ws.Cells.Item($rowNum, 2) = [string]$row[1]
        $rowNum++
    }

    $ws.Range("A1", "B$($rowNum - 1)").Columns.AutoFit()

    $wb.Save()
    $wb.Close()
    $excel.Quit()

    Write-Host "[OK] Laptop details saved to: $outputPath"
} catch {
    Write-Error "Excel COM error: $_"
    Write-Warning "Falling back to CSV export..."
    $csvPath = $outputPath -replace "\.xlsx$", ".csv"
    $rows | ForEach-Object { [PSCustomObject]@{Feature = $_[0]; Info = $_[1]} } |
        Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] Laptop details saved to (CSV): $csvPath"
} finally {
    if ($excel) { [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
