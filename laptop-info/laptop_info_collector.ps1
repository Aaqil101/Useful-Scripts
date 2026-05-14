# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[WARNING] Not running as Administrator. Attempting to re-launch elevated..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Write-Host "[OK] Running as Administrator." -ForegroundColor Green

# --- Error logging setup ---
$scriptDir = Split-Path -Parent $PSCommandPath
$logPath = Join-Path $scriptDir "Laptop_Info_Errors.log"
function Write-Log {
    param([string]$Context, [string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Context] $Message"
    Add-Content -Path $logPath -Value $entry
    Write-Warning $entry
}
"===== Laptop Info Collection $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Set-Content -Path $logPath

$conditionNotes = Read-Host -Prompt "Enter condition notes (scratches, accessories, missing items, etc.)"

# --- Warranty ---
$warrantyOptions = @("1) No warranty", "2) Shop warranty", "3) Company/brand warranty")
Write-Host "Warranty type:"
$warrantyOptions | ForEach-Object { Write-Host "  $_" }
do {
    $warrantyChoice = Read-Host -Prompt "Enter warranty type (1, 2, or 3)"
} while ($warrantyChoice -notmatch '^[123]$')

$warrantyType = switch ($warrantyChoice) {
    "1" { "No warranty" }
    "2" {
        $wShop    = Read-Host -Prompt "Shop warranty - enter duration (e.g. 3 months, 1 year)"
        $wDetails = Read-Host -Prompt "Shop name or details (optional)"
        if ($wDetails) { "Shop warranty: $wShop ($wDetails)" } else { "Shop warranty: $wShop" }
    }
    "3" {
        $wDuration = Read-Host -Prompt "Brand/company warranty - enter duration (e.g. 1 year)"
        $wProvider = Read-Host -Prompt "Provider name (e.g. Lenovo, Dell, HP)"
        "Brand warranty: $wDuration ($wProvider)"
    }
}

# --- Price input with validation ---
do {
    $priceInput = Read-Host -Prompt "Enter price in LKR (numbers only, e.g. 48450)"
    $priceValid = $priceInput -match '^\d+(\.\d{1,2})?$'
    if (-not $priceValid) { Write-Host "[WARNING] Invalid price. Please enter a numeric value (e.g. 48450)." -ForegroundColor Yellow }
} while (-not $priceValid)
$price = $priceInput

# --- System / Brand / Model ---
try {
    $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $brand = $system.Manufacturer
    $model = $system.Model
    $product = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
    $productName = $product.Name
    $productVersion = $product.Version  # Lenovo stores friendly name here (e.g. "ThinkPad T430")
} catch { $brand = "N/A"; $model = "N/A"; $productName = "N/A"; $productVersion = "N/A"; Write-Log "System" "Could not retrieve system info: $_" }

# Priority: Lenovo Version field > ProductName > Model (machine type code fallback)
$displayModel = if ($brand -match "Lenovo|IBM" -and $productVersion -and $productVersion -notmatch '^N/A$|^Lenovo|^None|^To be filled|^Not Defined') {
    $productVersion
} elseif ($productName -and $productName -ne "N/A" -and $productName -notmatch '^System|Product|To be filled') {
    $productName
} else {
    $model
}
$laptopName = ("$brand $displayModel" -replace '[^\w .-]', '_').Trim()
$outputName = "${laptopName}.csv"
$outputPath = Join-Path $scriptDir $outputName

# --- Serial Number ---
try {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $serial = $bios.SerialNumber
    if ($serial -match "O\.?E\.?M\.?|To be filled|System Serial|Default") { $serial = "N/A" }
} catch { $serial = "N/A"; Write-Log "Serial" "Could not retrieve serial number: $_" }

# --- Operating System ---
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $osInfo = "$($os.Caption) ($($os.OSArchitecture))"
} catch { $osInfo = "N/A"; Write-Log "OS" "Could not retrieve OS info: $_" }

# --- Processor ---
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
    $cpuInfo = "$($cpu.Name) ($($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads)"
} catch { $cpuInfo = "N/A"; Write-Log "Processor" "Could not retrieve CPU info: $_" }

# --- RAM ---
try {
    $ramSticks = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop
    $totalRAM = ($ramSticks | Measure-Object -Property Capacity -Sum).Sum / 1GB
    $ramParts = @()
    $i = 1
    foreach ($stick in $ramSticks) {
        $cap   = [math]::Round($stick.Capacity / 1GB)
        $speed = $stick.Speed
        $form  = if ($stick.FormFactor -eq 12) { "SODIMM" } elseif ($stick.FormFactor -eq 8) { "DIMM" } else { "unknown" }
        # Determine DDR generation from MemoryType (or SMBIOSMemoryType for newer sticks)
        $ddrGen = switch ($stick.SMBIOSMemoryType) {
            24 { "DDR3" }; 26 { "DDR4" }; 34 { "DDR5" }
            default {
                switch ($stick.MemoryType) {
                    24 { "DDR3" }; 26 { "DDR4" }; 34 { "DDR5" }
                    default {
                        # Speed-based heuristic fallback
                        if    ($speed -le 1600 -and $speed -ge 800)  { "DDR3" }
                        elseif($speed -le 3200 -and $speed -ge 1866) { "DDR4" }
                        elseif($speed -ge 4800)                      { "DDR5" }
                        else  { "DDR?" }
                    }
                }
            }
        }
        $ramParts += "Slot ${i}: ${cap}GB $ddrGen ${speed}MHz $form"
        $i++
    }
    $ramDetailStr = $ramParts -join " | "
    # Summary uses first stick's DDR gen (they're always the same type in a laptop)
    $ddrSummary = if ($ramSticks[0]) {
        $s = $ramSticks[0]
        $g = switch ($s.SMBIOSMemoryType) {
            24{"DDR3"};26{"DDR4"};34{"DDR5"}
            default{ switch($s.MemoryType){24{"DDR3"};26{"DDR4"};34{"DDR5"};default{
                if($s.Speed -le 1600 -and $s.Speed -ge 800){"DDR3"}
                elseif($s.Speed -le 3200 -and $s.Speed -ge 1866){"DDR4"}
                elseif($s.Speed -ge 4800){"DDR5"} else{"DDR?"}}} }
        }
        $g
    } else { "" }
} catch { $totalRAM = "N/A"; $ramDetailStr = "N/A"; $ddrSummary = ""; Write-Log "RAM" "Could not retrieve RAM info: $_" }

# --- Storage ---
try {
    $disks = Get-PhysicalDisk -ErrorAction Stop
    $storageRows = @()

    # Common marketed sizes in GB (base-10). We snap raw size to nearest.
    $marketSizes = @(120,128,160,180,200,240,256,320,360,480,500,512,640,720,750,960,1000,1024,2000,2048,3000,4000)

    foreach ($disk in $disks) {
        # Use base-10 GB (how manufacturers advertise) for display size
        $rawGB = $disk.Size / 1000000000
        # Snap to nearest marketed size if within 8% tolerance, else round normally
        $snapped = $marketSizes | Sort-Object { [math]::Abs($_ - $rawGB) } | Select-Object -First 1
        $sizeGB  = if ([math]::Abs($snapped - $rawGB) / $rawGB -lt 0.08) { $snapped } else { [math]::Round($rawGB) }

        # Media type: use reported value, fall back to model name heuristic for older drives
        $isNVMe = $disk.BusType -eq 11
        $mediaLabel = switch ($disk.MediaType) {
            1 { "HDD" }; 2 { "SSD" }; 3 { "SCM" }
            default {
                $name = $disk.FriendlyName.ToUpper()
                if    ($isNVMe)                              { "SSD" }
                elseif($name -match "SSD|SOLID|FLASH|EVO|PRO|SSDSC|SSDPEKNW|MZNLN|MZVLB") { "SSD" }
                elseif($name -match "HDD|HTS|HDP|HDT|WDC|TOSHIBA MQ|ST\d|WD\d|HGST") { "HDD" }
                else  { "HDD" }   # safe default for spinning era drives
            }
        }

        # Bus label prefix
        $busLabel = if ($isNVMe) { "NVMe " } elseif ($disk.BusType -eq 8) { "mSATA " } else { "" }

        $driveStr = "${sizeGB}GB ${busLabel}${mediaLabel} ($($disk.FriendlyName))"
        $storageRows += $driveStr
    }
} catch { $storageRows = @(); Write-Log "Storage" "Could not retrieve disk info: $_" }

# --- Graphics ---
try {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
    $gpuParts = @()
    foreach ($gpu in $gpus) {
        $vram = if ($gpu.AdapterRAM) { "$([math]::Round($gpu.AdapterRAM / 1GB, 1))GB" } else { "?" }
        $gpuParts += "$($gpu.Name) ($vram)"
    }
    $gpuInfo = $gpuParts -join " | "
} catch { $gpuInfo = "N/A"; Write-Log "Graphics" "Could not retrieve GPU info: $_" }

# --- Screen / Display ---
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $w = $bounds.Width; $h = $bounds.Height
    $resolution = "${w}x${h}"

    # Map resolution to marketing name
    $resName = if    ($w -eq 3840 -and $h -eq 2160) { "4K UHD" }
               elseif($w -eq 2560 -and $h -eq 1600) { "WQXGA" }
               elseif($w -eq 2560 -and $h -eq 1440) { "QHD" }
               elseif($w -eq 2560 -and $h -eq 1080) { "UW-FHD" }
               elseif($w -eq 1920 -and $h -eq 1200) { "WUXGA" }
               elseif($w -eq 1920 -and $h -eq 1080) { "Full HD" }
               elseif($w -eq 1600 -and $h -eq 900)  { "HD+" }
               elseif($w -eq 1366 -and $h -eq 768)  { "HD" }
               elseif($w -eq 1280 -and $h -eq 800)  { "WXGA" }
               else  { "${w}x${h}" }

    # Try to get panel type from PnP (works on many modern laptops)
    $panelType = "N/A"
    $monitorPnp = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.Class -eq "Monitor" -and $_.Status -eq "OK"
    } | Select-Object -First 1
    if ($monitorPnp) {
        $fn = $monitorPnp.FriendlyName
        if     ($fn -match "OLED")    { $panelType = "OLED" }
        elseif ($fn -match "IPS")     { $panelType = "IPS" }
        elseif ($fn -match "TN")      { $panelType = "TN" }
        elseif ($fn -match "VA")      { $panelType = "VA" }
    }

    # Try to get physical size via WmiMonitorBasicDisplayParams
    $displaySize = "N/A"
    try {
        $mon = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop | Select-Object -First 1
        if ($mon -and $mon.MaxHorizontalImageSize -gt 0 -and $mon.MaxVerticalImageSize -gt 0) {
            $diagCm = [math]::Sqrt([math]::Pow($mon.MaxHorizontalImageSize,2) + [math]::Pow($mon.MaxVerticalImageSize,2))
            $diagIn = [math]::Round($diagCm / 2.54, 1)
            $displaySize = "${diagIn}`""
        }
    } catch {}

    # Build display string
    $displayInfo = if ($displaySize -ne "N/A") { "$displaySize $resName ($resolution)" } else { "$resName ($resolution)" }
    if ($panelType -ne "N/A") { $displayInfo += ", $panelType" }
} catch { $resolution = "N/A"; $displayInfo = "N/A"; Write-Log "Screen" "Could not retrieve screen info: $_" }

# --- Touchscreen ---
try {
    $touch = Get-PnpDevice | Where-Object {
        $_.Class -eq "HIDClass" -and $_.Status -eq "OK" -and
        ($_.FriendlyName -match "touch|digitizer|pen|surface")
    }
    $touchscreen = if ($touch) { "Yes" } else { "No" }
} catch { $touchscreen = "N/A"; Write-Log "Touchscreen" "Could not detect touchscreen: $_" }

# --- Battery ---
try {
    $batReportPath = Join-Path $scriptDir "battery-report.html"
    powercfg /batteryreport /output $batReportPath | Out-Null
    if (Test-Path $batReportPath) {
        $batHtml = Get-Content $batReportPath -Raw
        $designCap = if ($batHtml -match 'DESIGN CAPACITY[\s\S]*?<td[^>]*>\s*([\d,]+)\s*mWh') { $matches[1] -replace ',' } else { "N/A" }
        $fullCap   = if ($batHtml -match 'FULL CHARGE CAPACITY[\s\S]*?<td[^>]*>\s*([\d,]+)\s*mWh') { $matches[1] -replace ',' } else { "N/A" }
        $cycleCount = if ($batHtml -match 'CYCLE COUNT[\s\S]*?<td[^>]*>\s*(\d+)') { $matches[1] } else { "N/A" }
        $batChem = if ($batHtml -match 'CHEMISTRY[\s\S]*?<td[^>]*>\s*(\w+)') { $matches[1] } else { "N/A" }
        if ($designCap -ne "N/A" -and $fullCap -ne "N/A" -and [int]$designCap -gt 0) {
            $healthStr = "$([math]::Round(([int]$fullCap / [int]$designCap) * 100, 1))%"
        } else { $healthStr = "N/A" }
        Remove-Item $batReportPath -Force
    } else {
        throw "Battery report not generated"
    }
} catch { $designCap = "N/A"; $fullCap = "N/A"; $cycleCount = "N/A"; $healthStr = "N/A"; $batChem = "N/A"; Write-Log "Battery" "Could not retrieve battery info: $_" }

# --- Wi-Fi ---
try {
    $wifi = Get-NetAdapter -Name "*Wi-Fi*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wifi) {
        $wifi = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Wireless|Wi-Fi|802\.11" } | Select-Object -First 1
    }
    $wifiInfo = if ($wifi) { "$($wifi.Name) -- $($wifi.InterfaceDescription)" } else { "N/A" }
} catch { $wifiInfo = "N/A"; Write-Log "WiFi" "Could not detect Wi-Fi adapter: $_" }

# --- Bluetooth ---
try {
    $bt = Get-PnpDevice | Where-Object { $_.Class -eq "Bluetooth" -and $_.Status -eq "OK" } | Select-Object -First 1
    $btInfo = if ($bt) { "Yes" } else { "No" }
} catch { $btInfo = "N/A"; Write-Log "Bluetooth" "Could not detect Bluetooth: $_" }

# --- Ports (unified: USB, video, card reader, audio, LAN) ---
try {
    $pnpAll   = Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -eq "OK" }
    $pnpNames = $pnpAll.FriendlyName -join " "
    $pnpHwIds = ($pnpAll | ForEach-Object { $_.HardwareID }) -join " "
    $gpuNames = (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue).VideoProcessor -join " "
    $allText  = "$pnpNames $pnpHwIds $gpuNames"

    $portParts = [System.Collections.Generic.List[string]]::new()

    # -- USB-A: count by checking USB hub child port counts ------------------
    $usb2Count = 0; $usb3Count = 0; $usb31Count = 0; $usb32Count = 0
    $usbHubs = Get-CimInstance Win32_USBHub -ErrorAction SilentlyContinue
    foreach ($hub in $usbHubs) {
        $desc = $hub.Description + " " + $hub.Name
        $numPorts = if ($hub.NumberOfPorts) { $hub.NumberOfPorts } else { 0 }
        if ($numPorts -eq 0) { continue }
        if    ($desc -match "USB 3.2|3\.2")  { $usb32Count  += $numPorts }
        elseif($desc -match "USB 3.1|3\.1")  { $usb31Count  += $numPorts }
        elseif($desc -match "USB 3|xHCI|SuperSpeed") { $usb3Count += $numPorts }
        elseif($desc -match "USB 2|EHCI|Enhanced")   { $usb2Count += $numPorts }
    }
    # Deduplicate: USB 3.x ports are also visible as USB 2 in WMI - subtract
    $usb2Count = [math]::Max(0, $usb2Count - $usb3Count - $usb31Count - $usb32Count)

    if ($usb32Count  -gt 0) { $portParts.Add("USB 3.2 x $usb32Count") }
    if ($usb31Count  -gt 0) { $portParts.Add("USB 3.1 x $usb31Count") }
    if ($usb3Count   -gt 0) { $portParts.Add("USB 3.0 x $usb3Count") }
    if ($usb2Count   -gt 0) { $portParts.Add("USB 2.0 x $usb2Count") }

    # -- USB-C / Thunderbolt -------------------------------------------------
    $tbCount   = ($pnpAll | Where-Object { $_.FriendlyName -match "Thunderbolt" }).Count
    $usbcCount = ($pnpAll | Where-Object { $_.FriendlyName -match "USB.C|USB Type.C|Type-C" }).Count
    if ($tbCount   -gt 0) { $portParts.Add("USB-C x $usbcCount (incl. $tbCount Thunderbolt)") }
    elseif ($usbcCount -gt 0) { $portParts.Add("USB-C x $usbcCount") }

    # -- Video outputs -------------------------------------------------------
    if ($allText -match "HDMI")                              { $portParts.Add("HDMI") }
    if ($allText -match "DisplayPort|mini DisplayPort|mDP") { $portParts.Add("DisplayPort") }
    if ($allText -match "VGA|D-Sub")                        { $portParts.Add("VGA") }
    if ($allText -match "DVI")                          { $portParts.Add("DVI") }

    # -- Card readers --------------------------------------------------------
    if ($allText -match "MicroSD|Micro SD|microSD")  { $portParts.Add("MicroSD card reader") }
    elseif ($allText -match "SD Card|SDCard|SDXC")   { $portParts.Add("SD card reader") }

    # -- Audio jack ----------------------------------------------------------
    if ($allText -match "Audio|Headphone|Realtek High|IDT High|Conexant") { $portParts.Add("Audio jack") }

    # -- LAN (built-in Ethernet) ----------------------------------------------
    $eth = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match "Ethernet|Realtek|Intel.*Gigabit|I219|I217|I218" -and
        $_.InterfaceDescription -notmatch "Wireless|Wi-Fi|802\.11|Virtual|Bluetooth"
    } | Select-Object -First 1
    if ($eth) { $portParts.Add("LAN ($($eth.InterfaceDescription -replace ' Gigabit.*','') Gigabit)") }
    else      { $portParts.Add("LAN: via adapter (check manually)") }

    $portsStr = if ($portParts.Count -gt 0) { $portParts -join ", " } else { "Check device manually" }
} catch { $portsStr = "N/A"; Write-Log "Ports" "Could not detect ports: $_" }
# Keep individual vars for backwards compat
$ethInfo   = if ($eth)  { $eth.InterfaceDescription } else { "N/A" }
$usbCount  = ($usb2Count + $usb3Count + $usb31Count + $usb32Count + $usbcCount + $tbCount)
$videoPortStr = $portsStr

# --- Optical Drive ---
try {
    $optical = Get-CimInstance Win32_CDROMDrive -ErrorAction Stop
    $opticalInfo = if ($optical) { "Yes -- $($optical.Name)" } else { "No" }
} catch { $opticalInfo = "N/A"; Write-Log "Optical" "Could not detect optical drive: $_" }


# ============================================================
# CSV Output
# ============================================================

# Helper: safely format capacity fields that may be "N/A"
function Format-mWh { param($val); if ($val -eq "N/A") { "N/A" } else { "$val mWh" } }
function Format-GB  { param($val); if ($val -eq "N/A") { "N/A" } else { "$val GB" } }

# Build storage rows dynamically (supports any number of drives)
$storageFixedRows = @()
for ($di = 0; $di -lt [math]::Max($storageRows.Count, 1); $di++) {
    $label = "Storage Drive $($di + 1)"
    $val   = if ($di -lt $storageRows.Count) { $storageRows[$di] } else { "N/A" }
    $storageFixedRows += [PSCustomObject]@{Feature = $label; Info = $val}
}

# RAM summary line: e.g. "12GB DDR3"
$ramSummary = if ($totalRAM -ne "N/A") {
    $t = [math]::Round($totalRAM)
    if ($ddrSummary) { "${t}GB $ddrSummary" } else { "${t}GB" }
} else { "N/A" }

$rows = @(
    [PSCustomObject]@{Feature = "Brand";                        Info = $brand}
    [PSCustomObject]@{Feature = "Model";                        Info = $displayModel}
    [PSCustomObject]@{Feature = "Serial Number";                Info = $serial}
    [PSCustomObject]@{Feature = "Operating System";             Info = $osInfo}
    [PSCustomObject]@{Feature = "Processor";                    Info = $cpuInfo}
    [PSCustomObject]@{Feature = "RAM";                          Info = $ramSummary}
    [PSCustomObject]@{Feature = "RAM Details";                  Info = $ramDetailStr}
) + $storageFixedRows + @(
    [PSCustomObject]@{Feature = "Graphics";                     Info = $gpuInfo}
    [PSCustomObject]@{Feature = "Display";                      Info = $displayInfo}
    [PSCustomObject]@{Feature = "Touchscreen";                  Info = $touchscreen}
    [PSCustomObject]@{Feature = "Battery Design Capacity";      Info = (Format-mWh $designCap)}
    [PSCustomObject]@{Feature = "Battery Full Charge Capacity"; Info = (Format-mWh $fullCap)}
    [PSCustomObject]@{Feature = "Battery Cycle Count";          Info = $cycleCount}
    [PSCustomObject]@{Feature = "Battery Health";               Info = $healthStr}
    [PSCustomObject]@{Feature = "Battery Chemistry";            Info = $batChem}
    [PSCustomObject]@{Feature = "Wi-Fi";                        Info = $wifiInfo}
    [PSCustomObject]@{Feature = "Bluetooth";                    Info = $btInfo}
    [PSCustomObject]@{Feature = "Optical Drive";                Info = $opticalInfo}
    [PSCustomObject]@{Feature = "Ports";                        Info = $portsStr}
    [PSCustomObject]@{Feature = "Condition Notes";              Info = $conditionNotes}
    [PSCustomObject]@{Feature = "Warranty";                     Info = $warrantyType}
    [PSCustomObject]@{Feature = "Price";                        Info = "LKR $([string]::Format('{0:N0}', [long]$price))"}
)

try {
    $rows | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] Laptop details saved to: $outputPath"
} catch {
    Write-Log "CSV" "Could not write CSV: $_"
    Write-Error "Failed to write output file: $_"
}
