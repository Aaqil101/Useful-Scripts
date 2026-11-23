# YouTube 1080p Downloader

[![Aaqil Ilyas](https://img.shields.io/badge/Profile-Aaqil%20Ilyas-blue.svg)](https://github.com/Aaqil101)
[![License: GPL v3.0](https://img.shields.io/badge/License-GPL_3.0-orange.svg)](https://github.com/Aaqil101/.config/blob/master/LICENSE)

## Overview

A PowerShell wrapper around `yt-dlp` and `ffmpeg` that batch-downloads YouTube
videos at **1080p 30fps** (configurable) and converts them into **H.264 MP4** files that any
editor (Premiere Pro, Resolve, Vegas, Shotcut) opens without complaining.

## Why 30fps, and why the transcode step?

1080p30 is usually served as native **H.264** (format 137), which every NLE opens
directly. In that case the script only **remuxes** it into MP4 — no re-encode, no
quality loss, and it takes about a second.

1080p**60**, by contrast, is normally **VP9** or **AV1**, which most Windows NLEs
either refuse to import or decode in software at a crawl. Those files are also
twice the work to encode. Use `-Fps 60` when you want that footage anyway; the
script then downloads the 60fps stream and re-encodes it to H.264.

Either way the flow is:

1. **Download** the best 1080p stream at the target frame rate.
2. **Convert** it to H.264 High + AAC 320 kbps MP4 with `-movflags +faststart`
   so it scrubs smoothly while editing — by remux if it is already H.264, by
   re-encoding if it is VP9/AV1.

If your editor handles VP9 fine, pass `-NoTranscode` and keep the native file.

## Requirements

| Tool       | Notes                                                        |
| ---------- | ------------------------------------------------------------ |
| PowerShell | 5.1 or newer (built into Windows 10/11)                       |
| yt-dlp     | Place `yt-dlp.exe` next to this script                       |
| ffmpeg     | Place `ffmpeg.exe` next to this script                       |
| JS runtime | Place `deno.exe` next to this script (recommended)            |

`yt-dlp` 2026+ needs a JavaScript runtime to extract YouTube formats. Without
one you get a warning and fewer formats — usually including the 60fps ones.
`deno.exe` is a single self-contained binary: download the
[Windows zip](https://github.com/denoland/deno/releases/latest), extract
`deno.exe` into this folder, done. Nothing is installed system-wide, so the
whole folder stays portable between PCs. `node.exe` or `bun.exe` also work.

Some ffmpeg builds (gyan-style *full* builds) hard-link `vulkan-1.dll`. If
`ffmpeg.exe` refuses to start, drop a copy of `vulkan-1.dll` into this folder
next to it — no system install needed.

Everything is found in this order: script folder, `bin\` subfolder, `PATH`.

## Files

```
youtube-downloader/
├── download_videos.cmd           Double-click entry point
├── download_youtube_videos.ps1   The script
├── videos.txt                    URL list (one per line, # for comments)
├── yt-dlp.exe                    You provide this
├── ffmpeg.exe                    You provide this
├── deno.exe                      You provide this (JS runtime for yt-dlp)
├── vulkan-1.dll                  Only if your ffmpeg build needs it
├── archive.txt                   Auto-created, tracks downloaded video IDs
└── downloads/
    ├── <title> [<id>].mkv        Native 1080p source
    ├── failed_urls.txt           Auto-created when something fails
    └── edit/
        └── <title> [<id>] - H264.mp4
```

## Usage

### Quick start

1. Put one YouTube URL per line in `videos.txt`.
2. Double-click **`download_videos.cmd`**.

The window stays open if anything fails so you can read the error. The `.cmd` is
just a wrapper that runs the PowerShell script with the execution policy bypassed,
so it also accepts every parameter below:

```powershell
.\download_videos.cmd -ListFormats
.\download_videos.cmd -HardwareEncoder nvenc -DeleteSource
```

### Basic

Edit `videos.txt`, then:

```powershell
.\download_youtube_videos.ps1
```

### Check what formats a video actually has

```powershell
.\download_youtube_videos.ps1 -ListFormats -Urls 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
```

This prints the full format table plus the exact stream the selector would pick.
Nothing is downloaded.

### Get 1080p60 instead (slower, needs a re-encode)

```powershell
.\download_youtube_videos.ps1 -Fps 60
```

### Download a single video to a different folder

```powershell
.\download_youtube_videos.ps1 -Urls 'https://youtu.be/dQw4w9WgXcQ' -OutputDir 'D:\Footage'
```

### Fast GPU encode and delete the source afterwards

```powershell
.\download_youtube_videos.ps1 -HardwareEncoder nvenc -DeleteSource
```

`nvenc` needs a GTX 600/700-series or newer card, `qsv` needs a working Intel
Quick Sync setup, `amf` needs an AMD GPU. On older hardware leave it at `none`.
With the default 1080p30 target you usually get a remux and need no encoder at all.

### Only download, no transcoding

```powershell
.\download_youtube_videos.ps1 -NoTranscode
```

### Ignore the execution policy

```powershell
powershell -ExecutionPolicy Bypass -File .\download_youtube_videos.ps1
```

## Parameters

| Parameter              | Default               | Description                                                        |
| ---------------------- | --------------------- | ------------------------------------------------------------------ |
| `-InputFile`           | `.\videos.txt`        | URL list; blank lines and `#` comments are ignored                 |
| `-Urls`                | —                     | Extra URLs (`-Urls 'url1','url2'`), playlists included with `-Playlist` |
| `-OutputDir`           | `.\downloads`         | Where media is saved                                               |
| `-Playlist`            | off                   | Download whole playlists instead of just the linked video          |
| `-Fps`                 | `30`                  | Target frame rate: `24`, `25`, `30`, `50` or `60`                  |
| `-StrictFps`           | off                   | Fail instead of falling back when the target frame rate is missing |
| `-ListFormats`         | off                   | Dry run: list formats and the chosen stream, download nothing      |
| `-NoTranscode`         | off                   | Keep the native VP9/AV1 file, skip ffmpeg                          |
| `-Crf`                 | `20`                  | H.264 quality, 0–51, lower is better/slower/larger                 |
| `-Preset`              | `veryfast`            | x264 speed preset; `medium` is ~2.5× slower                        |
| `-HardwareEncoder`     | `none`                | `none`, `nvenc`, `qsv` or `amf` (GPU encode)                       |
| `-DeleteSource`        | off                   | Delete the native file after a successful transcode                |
| `-Force`               | off                   | Ignore `archive.txt` and re-download                               |
| `-CookiesFromBrowser`  | —                     | e.g. `chrome`; for age-restricted or members-only videos           |
| `-ConcurrentFragments` | `4`                   | Parallel fragments per video                                       |
| `-JsRuntime`           | auto                  | `deno`, `node`, `bun` or `name:path`; auto-detected                |

## Behaviour details

- **Skip already-downloaded videos.** `archive.txt` records every video ID, so
  re-running the same list only fetches new entries. `-Force` overrides it.
- **Resume and retry.** Partial downloads continue, and each request retries up
  to 10 times per fragment. A failed URL does not stop the batch.
- **Idempotent transcoding.** The transcode pass walks every source in
  `downloads\` and skips any file that already has an output in `downloads\edit\`.
  An interrupted batch picks up where it left off.
- **Live streams are skipped** via `--match-filter "!is_live"`.
- **Filenames** are Windows-safe and trimmed to 150 characters.
- **Exit code** is `0` only when everything succeeded; failures are listed in
  `downloads\failed_urls.txt`.

## Performance

With the default 1080p30 target, most videos are native H.264 and get remuxed in
about a second — no encoding at all. Only VP9/AV1 sources, or `-Fps 60`, need a
real encode, and 60fps is roughly twice the work of 30fps.

These are real measurements of a 35s 1080p60 clip (2154 frames) on an i3-4160
(2 cores / 4 threads):

| Encode                          | Time   | Speed        | Frames/s |
| ------------------------------- | ------ | ------------ | -------- |
| decode only (no encode)         | 7.5s   | 4.66×        | 289      |
| libx264 `medium` CRF 18         | 80.9s  | 0.43×        | 27       |
| libx264 `veryfast` CRF 18       | 32.4s  | 1.08×        | 67       |
| **libx264 `veryfast` CRF 20**   | 31.1s  | 1.13×        | 69       |
| libx264 `ultrafast` CRF 22      | 15.5s  | 2.27×        | 140      |

That is why the defaults are `veryfast` / CRF 20 — `medium` would take ~23
minutes for a 10-minute video on that machine. Decoding is only ~9% of the time,
so the encode itself is the cost. GPU encoding (`nvenc`/`qsv`/`amf`) is 5-30×
faster than any CPU preset if your hardware supports it.

## Troubleshooting

| Symptom | Cause and fix |
| ------- | ------------- |
| `ffmpeg.exe could not start (exit code -1073741515)` | `STATUS_DLL_NOT_FOUND`. Some builds hard-link `vulkan-1.dll`, which is not part of a stock Windows install. Drop a `vulkan-1.dll` next to `ffmpeg.exe` (that is all it needs), install the [Vulkan Runtime](https://sdk.lunarg.com/sdk/download/latest/windows/vulkan-runtime-components.zip), or use the gyan *essentials* build. |
| `Requested format is not available` with `-StrictFps` | The video has no 1080p stream at the requested frame rate. Drop `-StrictFps` to accept a different rate. |
| `Sign in to confirm you're not a bot` | YouTube rate limiting. Update yt-dlp (`yt-dlp.exe -U`) or pass `-CookiesFromBrowser chrome`. |
| `No JavaScript runtime found` | Drop `deno.exe` next to the script (see Requirements). Without it yt-dlp warns that some formats are missing — usually the 60fps ones. |
| Transcode is very slow | It is CPU-bound. `-Preset veryfast` (default) is ~2.5× faster than `medium`; `ultrafast` is ~5× but degrades quality. On a dual-core machine that is the ceiling — see Performance. |
| Output is huge | CRF 20 is the default. `-Crf 22`–`24` shrinks files further; `-DeleteSource` reclaims the native copy. |
| A source file is transcoded twice | Not possible — the output name is derived from the source basename, so an existing `... - H264.mp4` is skipped. |

## Notes

- Downloading content you do not own may breach YouTube's Terms of Service.
  Use this on material you have the rights to.
- `ffmpeg.exe`, `yt-dlp.exe`, `deno.exe`, `node.exe`, `bun.exe`,
  `downloads/` and `archive.txt` are git-ignored.

## License

This script is released under the [GPL-3.0 license](https://www.gnu.org/licenses/gpl-3.0.en.html).
