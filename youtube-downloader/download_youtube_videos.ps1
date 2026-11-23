#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads a list of YouTube videos at 1080p30 (configurable) and converts
    them to editing-friendly H.264 MP4 files.

.DESCRIPTION
    Reads YouTube URLs from a text file (one per line, '#' for comments) and/or
    from -Urls, downloads the best 1080p stream at the target frame rate with
    yt-dlp, then converts each new file to H.264/AAC MP4 with ffmpeg in a
    separate "edit" folder.

    1080p30 is usually served natively as H.264, so those files are only remuxed
    (no re-encode, no quality loss, no encode time). Anything only available as
    VP9/AV1 gets transcoded, because most NLEs on Windows handle VP9 badly.

    yt-dlp.exe, ffmpeg.exe and a JavaScript runtime (deno.exe) are expected
    next to this script (or in .\bin\). Put copies there, or have them on PATH.

.PARAMETER InputFile
    Text file with one URL per line. Defaults to .\videos.txt.

.PARAMETER Urls
    Extra URLs passed directly on the command line.

.PARAMETER OutputDir
    Where downloads go. Defaults to .\downloads.

.PARAMETER Playlist
    Allow whole playlists. By default only the single video in the URL is taken.

.PARAMETER Fps
    Target frame rate. Default 30, which YouTube usually serves as native H.264
    (so it only needs a remux). Use 60 for smooth slow-motion footage; 1080p60 is
    almost always VP9/AV1 and therefore needs a real re-encode.

.PARAMETER StrictFps
    Fail instead of falling back when a video has no 1080p stream at the target
    frame rate.

.PARAMETER ListFormats
    Dry run: show the available formats and what would be picked, download nothing.

.PARAMETER NoTranscode
    Keep the native VP9/AV1 file and skip ffmpeg entirely.

.PARAMETER PreferH264
    Prefer YouTube's native H.264 stream when the upload has one. Those files are
    remuxed instead of re-encoded, so no quality is lost and no encode time is
    spent. Default on; disable with -PreferH264:$false.

.PARAMETER Crf
    x264 quality, lower is better and slower. Default 20, which is visually
    transparent for an editing source. Use 16-18 for near-lossless.

.PARAMETER Preset
    x264 speed preset. Default veryfast: roughly 2.5x faster than medium, which
    matters a lot on a dual-core machine. Use medium or slow on a fast CPU.

.PARAMETER HardwareEncoder
    Use a GPU encoder instead of libx264: none, nvenc, qsv or amf.

.PARAMETER DeleteSource
    Delete the native download after a successful transcode.

.PARAMETER Force
    Ignore archive.txt and re-download videos that were already fetched.

.PARAMETER CookiesFromBrowser
    e.g. chrome or firefox. Needed for age-restricted or members-only videos.

.PARAMETER ConcurrentFragments
    Parallel fragment downloads per video. Default 4.

.PARAMETER JsRuntime
    JavaScript runtime for yt-dlp's YouTube extraction: deno, node or bun.
    A portable deno.exe/node.exe/bun.exe placed next to the script is used
    automatically, then PATH is checked (deno, node, bun). Without a runtime,
    some formats (often the 1080p60 ones) are missing.

.EXAMPLE
    .\download_youtube_videos.ps1

.EXAMPLE
    .\download_youtube_videos.ps1 -ListFormats -Urls 'https://youtu.be/dQw4w9WgXcQ'

.EXAMPLE
    .\download_youtube_videos.ps1 -Fps 60 -DeleteSource
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string[]]$Urls,
    [string]$OutputDir,
    [switch]$Playlist,
    [ValidateSet(24, 25, 30, 50, 60)]
    [int]$Fps = 30,
    [switch]$StrictFps,
    [switch]$ListFormats,
    [switch]$NoTranscode,
    [bool]$PreferH264 = $true,
    [ValidateRange(0, 51)]
    [int]$Crf = 20,
    [ValidateSet('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow')]
    [string]$Preset = 'veryfast',
    [ValidateSet('none', 'nvenc', 'qsv', 'amf')]
    [string]$HardwareEncoder = 'none',
    [switch]$DeleteSource,
    [switch]$Force,
    [string]$CookiesFromBrowser,
    [ValidateRange(1, 16)]
    [int]$ConcurrentFragments = 4,
    [string]$JsRuntime
)

$ErrorActionPreference = 'Continue'

# --- Paths ---
$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $InputFile) { $InputFile = Join-Path $scriptDir 'videos.txt' }
if (-not $OutputDir) { $OutputDir = Join-Path $scriptDir 'downloads' }
$archivePath = Join-Path $scriptDir 'archive.txt'
$editDir = Join-Path $OutputDir 'edit'
$failedPath = Join-Path $OutputDir 'failed_urls.txt'
$sourceExtensions = @('.mkv', '.mp4', '.webm', '.mov', '.flv')

# --- Console helpers ---
function Write-Step { param([string]$Message) Write-Host "`n== $Message ==" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Gray }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$([int]$Bytes) B"
}

# --- Tool discovery ---
function Resolve-Tool {
    param([string]$Name, [string]$Hint)

    $candidates = @(
        (Join-Path $scriptDir "$Name.exe"),
        (Join-Path $scriptDir "bin\$Name.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    Write-Err "$Name was not found. $Hint"
    return $null
}

# A JavaScript runtime is required by modern yt-dlp for YouTube extraction.
# Prefer a portable copy next to the script so the folder works on any PC.
function Resolve-JsRuntime {
    param([string]$Override)

    if ($Override) { return $Override }

    $runtimes = @(
        @{ Name = 'deno'; Exe = 'deno.exe' }
        @{ Name = 'node'; Exe = 'node.exe' }
        @{ Name = 'bun'; Exe = 'bun.exe' }
    )

    foreach ($runtime in $runtimes) {
        foreach ($dir in @($scriptDir, (Join-Path $scriptDir 'bin'))) {
            $candidate = Join-Path $dir $runtime.Exe
            if (Test-Path -LiteralPath $candidate) {
                return ('{0}:{1}' -f $runtime.Name, (Resolve-Path -LiteralPath $candidate).Path)
            }
        }
    }

    foreach ($runtime in $runtimes) {
        if (Get-Command $runtime.Name -ErrorAction SilentlyContinue) {
            return $runtime.Name
        }
    }

    return $null
}

# --- URL input ---
function Get-VideoUrlList {
    param([string]$Path, [string[]]$ExtraUrls)

    $list = New-Object System.Collections.Generic.List[string]

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        foreach ($line in (Get-Content -LiteralPath $Path)) {
            $trimmed = $line.Trim()
            if (-not $trimmed) { continue }
            if ($trimmed.StartsWith('#')) { continue }
            $list.Add($trimmed)
        }
    } elseif ($Path) {
        Write-Warn "Input file not found: $Path"
    }

    if ($ExtraUrls) {
        foreach ($url in $ExtraUrls) {
            if ($url -and $url.Trim()) { $list.Add($url.Trim()) }
        }
    }

    return ($list | Select-Object -Unique)
}

function Get-VideoId {
    param([string]$Url)
    if ($Url -match '(?:v=|/shorts/|youtu\.be/|/live/|/embed/)([A-Za-z0-9_-]{11})') {
        return $Matches[1]
    }
    return $null
}

# ============================================================================
# Preflight
# ============================================================================
Write-Host "YouTube 1080p$Fps downloader" -ForegroundColor Magenta
Write-Info "Script folder: $scriptDir"

Write-Step 'Checking tools'
$ytDlp = Resolve-Tool -Name 'yt-dlp' -Hint "Place yt-dlp.exe next to this script ($scriptDir) or in $scriptDir\bin."
if (-not $ytDlp) { exit 1 }
$ytDlpVersion = (& $ytDlp --version 2>&1 | Select-Object -First 1)
Write-Ok "yt-dlp   $ytDlpVersion  ($ytDlp)"

$jsRuntimeName = Resolve-JsRuntime -Override $JsRuntime
$jsArgs = @()
if ($jsRuntimeName) {
    $jsArgs = @('--js-runtimes', $jsRuntimeName)
    Write-Ok "js runtime $jsRuntimeName"
} else {
    Write-Warn 'No JavaScript runtime found. yt-dlp needs one for YouTube; without it some formats (often the high frame rate ones) are missing.'
    Write-Warn "Drop deno.exe next to this script ($scriptDir) - it is a single file, no install."
    Write-Warn 'Or install Node.js/Deno, or pass -JsRuntime node.'
}

$ffmpeg = $null
if (-not $NoTranscode -and -not $ListFormats) {
    $ffmpeg = Resolve-Tool -Name 'ffmpeg' -Hint "Place ffmpeg.exe next to this script ($scriptDir) or in $scriptDir\bin, or use -NoTranscode."
    if (-not $ffmpeg) { exit 1 }

    $ffmpegOut = & $ffmpeg -hide_banner -version 2>&1
    if ($LASTEXITCODE -ne 0) {
        $ffmpegCode = $LASTEXITCODE
        Write-Err "ffmpeg.exe could not start (exit code $ffmpegCode)."
        if ($ffmpegCode -eq -1073741515) {
            Write-Warn 'Exit code -1073741515 is STATUS_DLL_NOT_FOUND.'
            Write-Warn 'This ffmpeg build hard-links vulkan-1.dll, which is not in C:\Windows\System32.'
            Write-Warn 'Install the Vulkan Runtime, or use an ffmpeg build that loads Vulkan lazily.'
        }
        Write-Warn 'Downloading is still possible with -NoTranscode.'
        exit 1
    }
    Write-Ok "ffmpeg   $(($ffmpegOut | Select-Object -First 1))  ($ffmpeg)"
} elseif ($ListFormats) {
    Write-Info 'Format listing only: ffmpeg is not needed.'
} else {
    Write-Info 'Transcoding disabled (-NoTranscode).'
}

# ============================================================================
# Format selection
# ============================================================================
$fpsCeiling = $Fps + 1
$nativeH264 = "bv*[height=1080][fps<=$fpsCeiling][vcodec^=avc1]+ba"
$anyAtFps = "bv*[height=1080][fps<=$fpsCeiling]+ba"
$nativeH264AnyFps = "bv*[height=1080][vcodec^=avc1]+ba"
$fullHd = "bv*[height=1080]+ba"
$bestAvailable = "bv*[height<=1080]+ba"

if ($StrictFps -and $PreferH264) {
    $formatSelector = "bv*[height=1080][fps=$Fps][vcodec^=avc1]+ba/bv*[height=1080][fps=$Fps]+ba/b[height=1080][fps=$Fps]"
    $formatNote = "1080p$Fps only (strict), native H.264 preferred"
} elseif ($StrictFps) {
    $formatSelector = "bv*[height=1080][fps=$Fps]+ba/b[height=1080][fps=$Fps]"
    $formatNote = "1080p$Fps only (strict)"
} elseif ($PreferH264) {
    $formatSelector = "$nativeH264/$anyAtFps/$nativeH264AnyFps/$fullHd/$bestAvailable"
    $formatNote = "native H.264 1080p up to ${Fps}fps, else any 1080p, else best"
} else {
    $formatSelector = "$anyAtFps/$fullHd/$bestAvailable"
    $formatNote = "1080p up to ${Fps}fps, else any 1080p, else best"
}
Write-Info "Format: $formatNote"

$mergeFormat = if ($NoTranscode) { 'mp4' } else { 'mkv' }
$outputTemplate = Join-Path $OutputDir '%(title)s [%(id)s].%(ext)s'

# ============================================================================
# URL list
# ============================================================================
$urls = @(Get-VideoUrlList -Path $InputFile -ExtraUrls $Urls)
if ($urls.Count -eq 0) {
    Write-Err "No video URLs found. Add one URL per line to $InputFile or pass -Urls."
    exit 1
}
Write-Info "$($urls.Count) URL(s) queued"

if ($ListFormats) {
    foreach ($url in $urls) {
        Write-Step "Formats: $url"

        & $ytDlp @jsArgs --no-warnings --no-playlist --list-formats $url
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Could not list formats for $url"
            continue
        }

        $picked = & $ytDlp @jsArgs --no-warnings --no-playlist --simulate -f $formatSelector `
            --print '%(format_id)s | %(height)s | %(fps)s fps | %(vcodec)s | %(tbr)s kbps' $url 2>&1
        if ($LASTEXITCODE -eq 0 -and $picked) {
            Write-Ok 'Selector would pick:'
            foreach ($line in $picked) { Write-Host "    $line" -ForegroundColor Green }
        } else {
            Write-Warn 'Selector would not match this video.'
        }
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
if (-not $NoTranscode -and -not (Test-Path -LiteralPath $editDir)) {
    New-Item -ItemType Directory -Path $editDir -Force | Out-Null
}

# ============================================================================
# Download
# ============================================================================
$downloadArgs = @(
    '--newline'
    '--continue'
    '--no-overwrites'
    '--retries', '10'
    '--fragment-retries', '10'
    '--retry-sleep', '5'
    '--concurrent-fragments', "$ConcurrentFragments"
    '--windows-filenames'
    '--trim-filenames', '150'
    '--match-filter', '!is_live'
    '--merge-output-format', $mergeFormat
    '-f', $formatSelector
    '-o', $outputTemplate
)
if (-not $Playlist) { $downloadArgs += '--no-playlist' }
$downloadArgs += $jsArgs
if ($CookiesFromBrowser) { $downloadArgs += '--cookies-from-browser', $CookiesFromBrowser }
if (-not $Force) { $downloadArgs += '--download-archive', $archivePath }

$downloadOk = 0
$downloadFailed = New-Object System.Collections.Generic.List[string]
$index = 0

foreach ($url in $urls) {
    $index++
    $videoId = Get-VideoId -Url $url
    $label = if ($videoId) { $videoId } else { $url }
    Write-Step "[$index/$($urls.Count)] Downloading $label"
    Write-Host "  $url" -ForegroundColor DarkGray

    $started = Get-Date
    & $ytDlp @downloadArgs $url 2>&1 | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    $elapsed = (Get-Date) - $started

    if ($exitCode -eq 0) {
        $downloadOk++
        Write-Ok "Finished $label in $([int]$elapsed.TotalSeconds)s"
    } else {
        $downloadFailed.Add($url)
        Write-Err "yt-dlp exited with code $exitCode for $label"
    }
}

# ============================================================================
# Transcode
# ============================================================================
$transcoded = 0
$remuxed = 0
$transcodeSkipped = 0
$transcodeFailed = New-Object System.Collections.Generic.List[string]

if (-not $NoTranscode) {
    $sources = @(Get-ChildItem -LiteralPath $OutputDir -File |
            Where-Object { $sourceExtensions -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name)

    Write-Step "Transcoding to H.264 ($($sources.Count) source file(s) in $OutputDir)"

    if ($sources.Count -eq 0) {
        Write-Warn 'No source files to transcode.'
    }

    $encoderArgs = switch ($HardwareEncoder) {
        'nvenc' { @('-c:v', 'h264_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', "$Crf", '-b:v', '0') }
        'qsv' { @('-c:v', 'h264_qsv', '-global_quality', "$Crf", '-preset', 'medium') }
        'amf' { @('-c:v', 'h264_amf', '-rc', 'cqp', '-qp_i', "$Crf", '-qp_p', "$Crf") }
        default { @('-c:v', 'libx264', '-preset', $Preset, '-crf', "$Crf") }
    }

    foreach ($source in $sources) {
        $target = Join-Path $editDir ("{0} - H264.mp4" -f $source.BaseName)

        if (Test-Path -LiteralPath $target) {
            $transcodeSkipped++
            Write-Info "Skip (already encoded): $($source.Name)"
            continue
        }

        # Detect the source codec so native H.264 files are remuxed, not re-encoded.
        $probe = & $ffmpeg -hide_banner -i $source.FullName 2>&1 |
            Select-String -Pattern 'Stream #.*Video:' |
            ForEach-Object { $_.Line }
        $alreadyH264 = ($probe -join ' ') -match 'Video:\s*h264'

        if ($alreadyH264) {
            Write-Host "`n  Remuxing $($source.Name)  ($(Format-Bytes $source.Length))" -ForegroundColor Cyan
            Write-Info 'Source is already H.264; copying streams without re-encoding.'
        } else {
            Write-Host "`n  Encoding $($source.Name)  ($(Format-Bytes $source.Length))" -ForegroundColor Cyan
        }
        $started = Get-Date

        $ffArgs = @(
            '-hide_banner'
            '-nostdin'
            '-loglevel', 'warning'
            '-stats'
            '-stats_period', '5'
            '-y'
            '-i', $source.FullName
            '-map', '0:v:0'
            '-map', '0:a:0?'
        )

        if ($alreadyH264) {
            $ffArgs += @('-c', 'copy')
        } else {
            $ffArgs += $encoderArgs
            $ffArgs += @(
                '-pix_fmt', 'yuv420p'
                '-c:a', 'aac'
                '-b:a', '320k'
            )
        }

        $ffArgs += @(
            '-movflags', '+faststart'
            $target
        )

        & $ffmpeg @ffArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $ffExit = $LASTEXITCODE
        $elapsed = (Get-Date) - $started

        if ($ffExit -eq 0 -and (Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -gt 0) {
            if ($alreadyH264) { $remuxed++ } else { $transcoded++ }
            $size = Format-Bytes (Get-Item -LiteralPath $target).Length
            Write-Ok "Done in $([int]$elapsed.TotalSeconds)s -> $size"

            if ($DeleteSource) {
                Remove-Item -LiteralPath $source.FullName -Force
                Write-Info "Deleted source: $($source.Name)"
            }
        } else {
            $transcodeFailed.Add($source.FullName)
            Write-Err "ffmpeg exited with code $ffExit for $($source.Name)"
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ============================================================================
# Report
# ============================================================================
Write-Step 'Summary'
Write-Host "  Downloaded      : $downloadOk of $($urls.Count)" -ForegroundColor Gray
Write-Host "  Download failed : $($downloadFailed.Count)" -ForegroundColor $(if ($downloadFailed.Count) { 'Red' } else { 'Gray' })
if (-not $NoTranscode) {
    Write-Host "  Transcoded      : $transcoded" -ForegroundColor Gray
    Write-Host "  Remuxed (H.264) : $remuxed" -ForegroundColor Gray
    Write-Host "  Already encoded : $transcodeSkipped" -ForegroundColor Gray
    Write-Host "  Transcode failed: $($transcodeFailed.Count)" -ForegroundColor $(if ($transcodeFailed.Count) { 'Red' } else { 'Gray' })
}

$editBytes = 0
if (Test-Path -LiteralPath $editDir) {
    $editBytes = (Get-ChildItem -LiteralPath $editDir -File | Measure-Object -Property Length -Sum).Sum
}
if ($editBytes) {
    Write-Host "  Edit folder size: $(Format-Bytes $editBytes)  ($editDir)" -ForegroundColor Gray
}

$allFailed = @($downloadFailed) + @($transcodeFailed)
if ($allFailed.Count -gt 0) {
    $allFailed | Set-Content -LiteralPath $failedPath -Encoding UTF8
    Write-Warn "Failures written to $failedPath"
    foreach ($failure in $allFailed) { Write-Host "  - $failure" -ForegroundColor DarkYellow }
    Write-Info 'Retry a download failure with -Force (it may already be in archive.txt).'
    exit 1
}

Write-Ok 'All done.'
exit 0
