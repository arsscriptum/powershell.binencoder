# PowerShell Binary File Encoder

This PowerShell tool allows you to **embed any binary file** (e.g. images, videos, executables) into either:

* a PowerShell `.ps1` script
* or a compiled `.dll` (C#) library

It provides an easy way to package, store, or transport binary data entirely in text form, with an included mechanism to restore the original file later. Compression and hashing are used for efficient storage and data integrity.

---

## Features

- Encode any binary file (e.g. `.mp4`, `.exe`, images)
- Output as either PowerShell script or compiled DLL
- Automatic compression with Gzip
- Splits large base64 strings into configurable chunks
- Automatically verifies MD5 hash after restoration
- Handles duplicate output file names safely

---

## How It Works

* Reads your binary file
* Compresses the binary data using Gzip
* Encodes it in Base64
* Outputs either:

  * a `.ps1` PowerShell script containing the Base64 data and restore functions
  * or a compiled `.dll` that contains methods to reconstruct the file

Restoration decompresses and writes back the original file, verifying its hash.

---

## Installation

Clone the repo and import the functions into your PowerShell session.

Or simply copy the function `Invoke-EncodeBinary` and helpers (like `Get-UniqueFilePath`) into your own scripts.

---

## Usage

### Encode as PowerShell Script

```powershell
Invoke-EncodeBinary -Path "data\SkatesMov.mp4" `
    -Destination "ps1" `
    -MaxChunkLength 512 `
    -Overwrite `
    -Mode "ps1"
```

* This creates:

  ```
  ps1\SkatesMov.ps1
  ```

* To restore the binary:

```powershell
# Import the generated script
. .\ps1\SkatesMov.ps1

# Restore the file
$path = Restore-FileSkatesMov
Write-Host "File restored to: $path"
```

---

### Encode as DLL

```powershell
Invoke-EncodeBinary -Path "data\SkatesMov.mp4" `
    -Destination "dll" `
    -MaxChunkLength 512 `
    -Overwrite `
    -Mode "dll"
```

* This creates:

  ```
  dll\SkatesMov.dll
  ```

* To restore the binary:

```powershell
Add-Type -Path "dll\SkatesMov.dll"

# Call the static method
$filePath = [MyLibrary.MyFileRestorer]::RestoreFileSkatesMov()

Write-Host "File restored to: $filePath"
```

---

## Parameters

| Parameter         | Description                                                                                    |
| ----------------- | ---------------------------------------------------------------------------------------------- |
| `-Path`           | Path to the binary file you want to encode.                                                    |
| `-Destination`    | Directory where the encoded file (.ps1 or .dll) is saved.                                      |
| `-MaxChunkLength` | Maximum length of each Base64 chunk in the generated file (default: 1024 bytes).               |
| `-Overwrite`      | Overwrite the output file if it already exists.                                                |
| `-OnlyData`       | If specified, generates only the data array (no restore functions).                            |
| `-ArrayName`      | Name of the generated Base64 chunks array in PowerShell output (default: Base64Chunks).        |
| `-Mode`           | Choose `"ps1"` to generate PowerShell script, or `"dll"` to generate a compiled .NET assembly. |

---

## Hash Verification

Restored files are verified using an MD5 hash. If the hash doesn’t match, the tool will warn you:

```
Invalid Hash!
```

---

## Example Workflow

```powershell
# Encode
Invoke-EncodeBinary -Path "data\SkatesMov.mp4" -Destination "ps1" -Mode "ps1" -MaxChunkLength 512 -Overwrite

# Import and restore
. .\ps1\SkatesMov.ps1
$path = Restore-FileSkatesMov
Write-Host "Recovered file saved as: $path"
```

---

## Testing

Run the provided test function:

```powershell
Test-InvokeEncodeBinary -Path ".\data\SkatesMov.mp4" -Mode "ps1"
Test-InvokeEncodeBinary -Path ".\data\SkatesMov.mp4" -Mode "dll"
```

---

## Requirements

* PowerShell 5.1 or later
* .NET SDK tools if compiling the DLL (must have `csc.exe` compiler)

---

## Notes

* Restored files are saved in your system temp folder with unique filenames to avoid overwriting.
* For large binaries, adjust `-MaxChunkLength` to avoid extremely large single-line strings.
