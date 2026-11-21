<#
.SYNOPSIS
    Converts PowerPoint decks to 6-up handout PDFs (landscape, black & white).

.DESCRIPTION
    For every .pptx / .ppt / .ppsx / .pps in a folder this script:
      * opens the file read-only in PowerPoint (the original is never saved),
      * sets the handout page to landscape,
      * lays the slides out 6 per page, 3 across / 2 down ("6 Slides Horizontal"),
      * removes the date and the page number from the handouts,
      * exports the handouts to PDF,
      * converts every page to grayscale so the PDF looks like PowerPoint's
        "Pure Black and White" print preview,
      * writes one PDF per deck to the output folder.

    If you want the original vector (colour) PDF instead, use -KeepColor.

.NOTES
    Needs Windows + Microsoft PowerPoint. Run it from Windows PowerShell 5.1;
    if you start it from PowerShell 7 it relaunches itself the right way.

.EXAMPLE
    .\convert_powerpoint_to_handout_pdf.ps1

    Converts every deck in the folder that contains the script into .\PDF.

.EXAMPLE
    .\convert_powerpoint_to_handout_pdf.ps1 -Path 'D:\Talks' -OutDir 'D:\Talks\Handouts' -Recurse -Force

    Converts all decks in D:\Talks and its subfolders, overwriting existing PDFs.

.EXAMPLE
    .\convert_powerpoint_to_handout_pdf.ps1 -Dpi 300 -KeepColor

    Sharper images, keep the original colours (vector PDF).

.EXAMPLE
    .\convert_powerpoint_to_handout_pdf.ps1 -KeepDateAndPageNumber

    Keep the date and page number on the handouts.
#>
[CmdletBinding()]
param(
    # Folder that contains the PowerPoint files.
    [string]$Path = $PSScriptRoot,

    # Folder for the PDFs. Defaults to <Path>\PDF.
    [string]$OutDir,

    # Also look in subfolders.
    [switch]$Recurse,

    # Overwrite PDFs that already exist. Without this, finished PDFs are skipped.
    [switch]$Force,

    # Open the output folder when the run finishes.
    [switch]$OpenWhenDone,

    # Resolution used when the pages are converted to grayscale. 200 is fine for
    # a laser printer, 300 is sharper but gives bigger files.
    [ValidateRange(96, 600)]
    [int]$Dpi = 200,

    # Keep the date and page number on the handouts (they are removed by default).
    [switch]$KeepDateAndPageNumber,

    # Do not draw a border around each slide (PowerPoint's print preview has one,
    # but its PDF export does not, so the script adds it).
    [switch]$NoFrame,

    # Keep the colour vector PDF (skip the grayscale conversion).
    [switch]$KeepColor
)

# ---------------------------------------------------------------------------
# Office interop needs the .NET Framework, so run under Windows PowerShell 5.1.
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    if (-not $PSCommandPath) { throw 'Save this code as a .ps1 file and run that file.' }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Path', $Path)
    if ($OutDir) { $argList += @('-OutDir', $OutDir) }
    if ($Recurse) { $argList += '-Recurse' }
    if ($Force) { $argList += '-Force' }
    if ($OpenWhenDone) { $argList += '-OpenWhenDone' }
    $argList += @('-Dpi', $Dpi)
    if ($KeepDateAndPageNumber) { $argList += '-KeepDateAndPageNumber' }
    if ($NoFrame) { $argList += '-NoFrame' }
    if ($KeepColor) { $argList += '-KeepColor' }
    & powershell.exe @argList
    exit (Get-Variable LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue)
}

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Folder not found: $Path"
}
$Path = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutDir) { $OutDir = Join-Path $Path 'PDF' }

if (Get-Process POWERPNT -ErrorAction SilentlyContinue) {
    throw 'PowerPoint is running. Close it first (the script has to start and stop its own hidden copy).'
}

# ---------------------------------------------------------------------------
# Locate the PowerPoint interop assemblies
# ---------------------------------------------------------------------------
$pia = [Reflection.Assembly]::LoadWithPartialName('Microsoft.Office.Interop.PowerPoint')
$office = [Reflection.Assembly]::LoadWithPartialName('office')
if (-not $pia -or -not $office) {
    throw 'Microsoft.Office.Interop.PowerPoint was not found. Is Microsoft PowerPoint installed?'
}

# ---------------------------------------------------------------------------
# Helper: the COM call has optional VARIANT parameters that PowerShell cannot
# bind, so the export itself is done from a tiny C# class.
# ---------------------------------------------------------------------------
if (-not ('HandoutPdf' -as [type])) {
    $code = @'
using System;
using Microsoft.Office.Core;
using Microsoft.Office.Interop.PowerPoint;

public static class HandoutPdf
{
    private static Application app;

    public static void Start()
    {
        if (app == null)
        {
            app = new Application();
            app.DisplayAlerts = PpAlertLevel.ppAlertsNone;
        }
    }

    public static void Export(string file, string outPdf, bool hideDateAndPageNumber, bool addFrame)
    {
        Start();
        _Presentation pres = null;
        try
        {
            pres = app.Presentations.Open(file,
                MsoTriState.msoTrue,    // ReadOnly
                MsoTriState.msoFalse,   // Untitled
                MsoTriState.msoFalse);  // WithWindow

            // Landscape handout page (msoOrientationHorizontal is landscape).
            pres.PageSetup.NotesOrientation = MsoOrientation.msoOrientationHorizontal;

            if (hideDateAndPageNumber)
            {
                pres.HandoutMaster.HeadersFooters.DateAndTime.Visible = MsoTriState.msoFalse;
                pres.HandoutMaster.HeadersFooters.SlideNumber.Visible = MsoTriState.msoFalse;

                // The properties above are not honoured by PDF export, the
                // placeholders still print, so remove them as well.
                for (int i = pres.HandoutMaster.Shapes.Count; i >= 1; i--)
                {
                    try
                    {
                        PpPlaceholderType t = pres.HandoutMaster.Shapes[i].PlaceholderFormat.Type;
                        if (t == PpPlaceholderType.ppPlaceholderDate ||
                            t == PpPlaceholderType.ppPlaceholderSlideNumber)
                        {
                            pres.HandoutMaster.Shapes[i].Delete();
                        }
                    }
                    catch { }
                }
            }

            // PowerPoint frames slides on paper, but not in exported PDFs, so draw
            // the frame on each slide (this copy only, the file is never saved).
            if (addFrame)
            {
                float w = pres.PageSetup.SlideWidth;
                float h = pres.PageSetup.SlideHeight;
                float weight = 0.75f;
                float inset = weight / 2f;
                for (int i = 1; i <= pres.Slides.Count; i++)
                {
                    try
                    {
                        Slide slide = pres.Slides[i];
                        Microsoft.Office.Interop.PowerPoint.Shape frame = slide.Shapes.AddShape(
                            MsoAutoShapeType.msoShapeRectangle,
                            inset, inset, w - 2 * inset, h - 2 * inset);
                        frame.Name = "PrintFrame";
                        frame.Fill.Visible = MsoTriState.msoFalse;
                        frame.Line.Visible = MsoTriState.msoTrue;
                        frame.Line.ForeColor.RGB = 0;
                        frame.Line.Weight = weight;
                    }
                    catch { }
                }
            }

            pres.ExportAsFixedFormat(
                outPdf,
                PpFixedFormatType.ppFixedFormatTypePDF,
                PpFixedFormatIntent.ppFixedFormatIntentPrint,
                MsoTriState.msoFalse,                                       // FrameSlides
                PpPrintHandoutOrder.ppPrintHandoutHorizontalFirst,          // 6 slides, across first
                PpPrintOutputType.ppPrintOutputSixSlideHandouts,            // 6 per page
                MsoTriState.msoFalse,                                       // PrintHiddenSlides
                RangeType: PpPrintRangeType.ppPrintAll);

            pres.Close();
            pres = null;
        }
        finally
        {
            if (pres != null) { try { pres.Close(); } catch { } }
        }
    }

    public static void Stop()
    {
        if (app != null)
        {
            try { app.Quit(); } catch { }
            app = null;
        }
    }
}
'@
    Add-Type -TypeDefinition $code -ReferencedAssemblies $pia.Location, $office.Location -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# PDF helpers: read a PDF, render every page to grayscale and write a new PDF.
# (PowerPoint's export has no colour option; this is how "Pure Black and White"
#  is baked into the file.)
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    })[0]

function Await($op, $type) {
    $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    $t.Result
}
function AwaitAction($op) {
    $t = $asTaskAction.Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null

function Write-Ascii([IO.BinaryWriter]$bw, [string]$text) {
    $bw.Write([Text.Encoding]::ASCII.GetBytes($text))
}

# A file that a WinRT renderer had open can stay locked for a moment.
function Remove-FileWithRetry {
    param([string]$FilePath)
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        if (-not (Test-Path -LiteralPath $FilePath)) { return }
        try {
            Remove-Item -LiteralPath $FilePath -Force -ErrorAction Stop
            return
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }
}

function Convert-PdfToGrayscale {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [int]$Dpi = 200,
        [int]$Quality = 90
    )

    # Page size in PDF points (PowerPoint writes /MediaBox as plain text).
    $raw = [IO.File]::ReadAllBytes($Source)
    $rawText = [Text.Encoding]::GetEncoding(28591).GetString($raw)
    $m = [regex]::Match($rawText, '/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]')
    if ($m.Success) {
        $pageW = [double]$m.Groups[3].Value - [double]$m.Groups[1].Value
        $pageH = [double]$m.Groups[4].Value - [double]$m.Groups[2].Value
    }
    else {
        $pageW = 720; $pageH = 540
    }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $wPt = $pageW.ToString('0.###', $inv)
    $hPt = $pageH.ToString('0.###', $inv)
    $pxW = [int][math]::Round($pageW / 72 * $Dpi)

    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)

    $matrix = New-Object System.Drawing.Imaging.ColorMatrix
    $lr = 0.299; $lg = 0.587; $lb = 0.114
    $matrix.Matrix00 = $lr; $matrix.Matrix01 = $lr; $matrix.Matrix02 = $lr
    $matrix.Matrix10 = $lg; $matrix.Matrix11 = $lg; $matrix.Matrix12 = $lg
    $matrix.Matrix20 = $lb; $matrix.Matrix21 = $lb; $matrix.Matrix22 = $lb
    $matrix.Matrix33 = 1.0; $matrix.Matrix44 = 1.0
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes
    $attributes.SetColorMatrix($matrix)

    $docStream = $null
    $docRandom = $null
    try {
        $docStream = New-Object IO.MemoryStream(, $raw)
        $docRandom = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($docStream)
        $doc = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromStreamAsync($docRandom)) ([Windows.Data.Pdf.PdfDocument])
    }
    catch {
        if ($docRandom) { $docRandom.Dispose() }
        if ($docStream) { $docStream.Dispose() }
        throw
    }
    $pageCount = [int]$doc.PageCount
    $totalObjects = 3 * $pageCount + 2

    $stream = [IO.File]::Create($Target)
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        Write-Ascii $writer "%PDF-1.4`n"
        $offsets = New-Object 'long[]' ($totalObjects + 1)

        $offsets[1] = $stream.Position
        Write-Ascii $writer "1 0 obj`n<< /Type /Catalog /Pages 2 0 R >>`nendobj`n"

        $kids = (0..($pageCount - 1) | ForEach-Object { "$(3 + 3 * $_) 0 R" }) -join ' '
        $offsets[2] = $stream.Position
        Write-Ascii $writer "2 0 obj`n<< /Type /Pages /Count $pageCount /Kids [$kids] >>`nendobj`n"

        for ($i = 0; $i -lt $pageCount; $i++) {
            $page = $doc.GetPage($i)

            $options = New-Object Windows.Data.Pdf.PdfPageRenderOptions
            $options.DestinationWidth = [uint32]$pxW
            $ras = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
            AwaitAction ($page.RenderToStreamAsync($ras, $options))

            $size = $ras.Size
            $reader = New-Object Windows.Storage.Streams.DataReader($ras.GetInputStreamAt(0))
            Await ($reader.LoadAsync([uint32]$size)) ([uint32]) | Out-Null
            $png = New-Object byte[] $size
            $reader.ReadBytes($png)

            $pngStream = New-Object IO.MemoryStream(, $png)
            $bitmap = [System.Drawing.Bitmap]::FromStream($pngStream)
            $gray = New-Object System.Drawing.Bitmap($bitmap.Width, $bitmap.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $graphics = [System.Drawing.Graphics]::FromImage($gray)
            $rect = New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)
            $graphics.DrawImage($bitmap, $rect, 0, 0, $bitmap.Width, $bitmap.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
            $graphics.Dispose()

            $jpgStream = New-Object IO.MemoryStream
            $gray.Save($jpgStream, $jpegCodec, $encParams)
            $jpg = $jpgStream.ToArray()
            $imgW = $gray.Width
            $imgH = $gray.Height

            $jpgStream.Dispose(); $gray.Dispose(); $bitmap.Dispose(); $pngStream.Dispose()
            $reader.Dispose(); $ras.Dispose(); $page.Dispose()

            $pageNum = 3 + 3 * $i
            $imgNum = 4 + 3 * $i
            $contentNum = 5 + 3 * $i

            $offsets[$pageNum] = $stream.Position
            Write-Ascii $writer "$pageNum 0 obj`n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $wPt $hPt] /Resources << /XObject << /Im0 $imgNum 0 R >> >> /Contents $contentNum 0 R >>`nendobj`n"

            $offsets[$imgNum] = $stream.Position
            Write-Ascii $writer "$imgNum 0 obj`n<< /Type /XObject /Subtype /Image /Width $imgW /Height $imgH /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length $($jpg.Length) >>`nstream`n"
            $writer.Write($jpg)
            Write-Ascii $writer "`nendstream`nendobj`n"

            $content = "q`n$wPt 0 0 $hPt 0 0 cm`n/Im0 Do`nQ`n"
            $contentBytes = [Text.Encoding]::ASCII.GetBytes($content)
            $offsets[$contentNum] = $stream.Position
            Write-Ascii $writer "$contentNum 0 obj`n<< /Length $($contentBytes.Length) >>`nstream`n"
            $writer.Write($contentBytes)
            Write-Ascii $writer "endstream`nendobj`n"
        }

        $xref = $stream.Position
        Write-Ascii $writer "xref`n0 $($totalObjects + 1)`n"
        Write-Ascii $writer "0000000000 65535 f `n"
        for ($n = 1; $n -le $totalObjects; $n++) {
            Write-Ascii $writer ("{0:D10} 00000 n `n" -f $offsets[$n])
        }
        Write-Ascii $writer "trailer`n<< /Size $($totalObjects + 1) /Root 1 0 R >>`nstartxref`n$xref`n%%EOF`n"
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
        if ($doc) { try { $doc.Dispose() } catch { } }
        if ($docRandom) { try { $docRandom.Dispose() } catch { } }
        if ($docStream) { try { $docStream.Dispose() } catch { } }
    }
}

# ---------------------------------------------------------------------------
# Collect the files
# ---------------------------------------------------------------------------
$patterns = '*.pptx', '*.ppt', '*.ppsx', '*.pps'
$files = foreach ($pattern in $patterns) {
    Get-ChildItem -LiteralPath $Path -Filter $pattern -File -Recurse:$Recurse -ErrorAction SilentlyContinue
}
$files = @($files | Where-Object { $_.Name -notlike '~$*' } | Sort-Object FullName -Unique)

if ($files.Count -eq 0) {
    Write-Warning "No PowerPoint files found in $Path"
    return
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    $null = New-Item -ItemType Directory -Path $OutDir -Force
}

"PowerPoint files : $($files.Count)"
"Output folder   : $OutDir"
"Colour mode     : $(if ($KeepColor) { 'colour (vector PDF)' } else { "black & white ($Dpi dpi)" })"
''

# ---------------------------------------------------------------------------
# Convert
# ---------------------------------------------------------------------------
$usedNames = @{}
$ok = 0
$skipped = 0
$failed = @()
$started = Get-Date
$tempFiles = New-Object System.Collections.Generic.List[string]

try {
    [HandoutPdf]::Start()

    for ($i = 0; $i -lt $files.Count; $i++) {
        $file = $files[$i]
        $label = "[$($i + 1)/$($files.Count)] $($file.Name)"

        # Unique output name (two decks with the same name in different folders)
        $base = $file.BaseName
        $name = "$base.pdf"
        $n = 1
        while ($usedNames.ContainsKey($name.ToLowerInvariant())) {
            $n++
            $name = "$base ($n).pdf"
        }
        $usedNames[$name.ToLowerInvariant()] = $true
        $target = Join-Path $OutDir $name

        if ((Test-Path -LiteralPath $target) -and -not $Force) {
            Write-Host "$label -> skipped, PDF already exists" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        $staging = "$target.tmp"
        try {
            # Fail fast (and clearly) when the PDF is open in a viewer.
            if (Test-Path -LiteralPath $target) {
                try {
                    $probe = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                    $probe.Dispose()
                }
                catch {
                    throw "$name is open in another program. Close the PDF and run again."
                }
            }

            # Unique temp file per deck: a reused path can still be locked by the
            # renderer that produced the PDF.
            $tempPdf = Join-Path ([IO.Path]::GetTempPath()) ("handout_" + [guid]::NewGuid().ToString('N') + ".pdf")
            $tempFiles.Add($tempPdf)

            [HandoutPdf]::Export($file.FullName, $tempPdf, [bool](-not $KeepDateAndPageNumber), [bool](-not $NoFrame))
            if (-not (Test-Path -LiteralPath $tempPdf)) {
                throw 'PowerPoint did not produce a PDF.'
            }

            # Build the new PDF next to the target, then swap it in last, so an
            # existing PDF is never left half written.
            if ($KeepColor) {
                Move-Item -LiteralPath $tempPdf -Destination $staging -Force
            }
            else {
                Convert-PdfToGrayscale -Source $tempPdf -Target $staging -Dpi $Dpi
                Remove-FileWithRetry -FilePath $tempPdf
            }
            Move-Item -LiteralPath $staging -Destination $target -Force

            $size = [math]::Round((Get-Item -LiteralPath $target).Length / 1KB)
            Write-Host "$label -> $name ($size KB)" -ForegroundColor Green
            $ok++
        }
        catch {
            if (Test-Path -LiteralPath $staging) { Remove-FileWithRetry -FilePath $staging }
            Write-Host "$label -> FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $failed += [pscustomobject]@{ File = $file.FullName; Error = $_.Exception.Message }
        }
    }
}
finally {
    [HandoutPdf]::Stop()
    foreach ($tmp in $tempFiles) { Remove-FileWithRetry -FilePath $tmp }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$elapsed = (Get-Date) - $started
''
"Done in $([math]::Round($elapsed.TotalSeconds)) s - converted: $ok, skipped: $skipped, failed: $($failed.Count)"
if ($failed.Count -gt 0) {
    ''
    'Failed files:'
    $failed | ForEach-Object { "  $($_.File)`n    $($_.Error)" }
}

if ($OpenWhenDone) { Invoke-Item -LiteralPath $OutDir }

if ($failed.Count -gt 0) { exit 1 }
