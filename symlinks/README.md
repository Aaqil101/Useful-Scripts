# Find Symlinks

[![Aaqil Ilyas](https://img.shields.io/badge/Profile-Aaqil%20Ilyas-blue.svg)](https://github.com/Aaqil101)
[![License: GPL v3.0](https://img.shields.io/badge/License-GPL_3.0-orange.svg)](https://github.com/Aaqil101/.config/blob/master/LICENSE)

## Overview

A PowerShell utility script to find all symbolic links across your Windows system that point to a specific directory (particularly useful for config folder management).

## Features

- **System-wide Search**: Scans all drives (or selected drives) in your system
- **Visual Progress Tracking**: Displays detailed progress bars for drives and folders
- **Selective Scanning**: Option to exclude removable drives and system directories
- **Comprehensive Reporting**:
  - Generates a detailed report of all symbolic links
  - Tracks and records errors encountered during scanning
  - Provides execution statistics and timing information
- **Performance Optimized**: Uses efficient directory traversal techniques
- **Flexible Configuration**: Multiple command-line parameters for customization

## Requirements

- Windows PowerShell 5.1 or higher
- Administrative privileges (recommended for system-wide scanning)

## Installation

1. Download the `symlinks/find_symlinks.ps1` file
2. Save it to a location of your choice
3. No additional installation required

## Usage

### Basic Usage

```powershell
.\find_symlinks.ps1
```

This will scan all drives for symbolic links pointing to `$env:USERPROFILE\Documents\GitHub\.config` and save results to your desktop.

### Advanced Usage

```powershell
.\Find-SymlinksPointingToConfig.ps1 -TargetPath "D:\YourConfigPath" -OutputFile "C:\Results\symlinks.txt" -SkipRemovableDrives -ExcludePaths @("C:\Program Files", "D:\Games")
```

### Running with PowerShell Execution Policy Restrictions

#### Option 1: Temporarily bypass the execution policy (safest for one-time use)

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Documents\GitHub\.config\symlinks\find_symlinks.ps1"
```

#### Option 2: Change the execution policy for your current session

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run the script normally.

### Parameters

| Parameter            | Description                               | Default                                                               |
| -------------------- | ----------------------------------------- | --------------------------------------------------------------------- |
| -TargetPath          | Directory to search for links pointing to | `$env:USERPROFILE\Documents\GitHub\.config`                           |
| -OutputFile          | Where to save the results                 | `$env:USERPROFILE\Documents\GitHub\.config\symlinks\SymbolicLink.txt` |
| -SkipRemovableDrives | Exclude removable drives from scan        | `false`                                                               |
| -ExcludePaths        | Array of paths to exclude from scanning   | System directories                                                    |

## Output Files

The script generates two potential output files:

1. **Main Results File**: List of all symbolic links found

    ```powershell
    C:\Path\To\Link -> $env:USERPROFILE\Documents\GitHub\.config\target
    ```

2. **Error Log File**: Created only if errors occur during scanning

    ```powershell
    Error processing C:\Path\To\Folder: Access is denied
    ```

## Performance Considerations

- **Runtime**: Scanning an entire system may take several minutes to hours, depending on:
  - Number and size of drives
  - System performance
  - Number of files and folders
- **Resource Usage**: Moderate CPU and disk I/O during operation
- **Recommendations**:
  - Run during periods of low system activity
  - Use the `-ExcludePaths` parameter to skip large directories you know won't contain relevant links

## Common Issues

| Issue                | Solution                                           |
| -------------------- | -------------------------------------------------- |
| Access denied errors | Run PowerShell as Administrator                    |
| Slow performance     | Use `-ExcludePaths` to skip irrelevant directories |
| Script hangs         | Check for network drives or large directories      |

## Contributing

Feel free to fork and enhance this script. Pull requests are welcome for:

- Performance improvements
- Additional features
- Bug fixes
- Documentation enhancements

## License

This script is released under the [GPL-3.0 license](https://www.gnu.org/licenses/gpl-3.0.en.html).
