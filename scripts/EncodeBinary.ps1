#╔════════════════════════════════════════════════════════════════════════════════╗
#║                                                                                ║
#║   EncodeBinary.ps1                                                             ║
#║   Powershell Binary Encoder                                                    ║
#║                                                                                ║
#╟────────────────────────────────────────────────────────────────────────────────╢
#║   Guillaume Plante <codegp@icloud.com>                                         ║
#║   Code licensed under the GNU GPL v3.0. See the LICENSE file for details.      ║
#╚════════════════════════════════════════════════════════════════════════════════╝


function Get-UniqueFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Original file path")]
        [string]$Path
    )

    # Split path into parts
    $directory = Split-Path $Path -Parent
    $fileName = Split-Path $Path -Leaf
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $ext = [System.IO.Path]::GetExtension($fileName)

    $newPath = $Path
    $counter = 1

    while (Test-Path $newPath) {
        $newName = "{0}-{1}{2}" -f $baseName, $counter, $ext
        $newPath = Join-Path $directory $newName
        $counter++
    }

    return $newPath
}


$FileRestoreCs = @"
using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace MyLibrary
{{
    public static class MyFileRestorer
    {{
        public static string {0}()
        {{
            {1}

            string outputFile = RestoreFromBase64Chunks(base64Chunks, recovered);
            string actualHash = ComputeMD5(outputFile);

            if (!string.Equals(actualHash, hashExpected, StringComparison.OrdinalIgnoreCase))
            {{
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(`"Invalid Hash!`");
                Console.ResetColor();
                return null;
            }}

            //Console.ForegroundColor = ConsoleColor.Green;
            //Console.WriteLine($`"File recovered successfully: {{outputFile}}`");
            //Console.ResetColor();

            return outputFile;
        }}

        public static string RestoreFromBase64Chunks(string[] chunks, string outputFile)
        {{
            string base64 = string.Join(`"`", chunks);
            byte[] compressedBytes = Convert.FromBase64String(base64);

            using var inputStream = new MemoryStream(compressedBytes);
            using var gzipStream = new GZipStream(inputStream, CompressionMode.Decompress);
            using var outputStream = new MemoryStream();

            gzipStream.CopyTo(outputStream);

            byte[] decompressedBytes = outputStream.ToArray();

            string uniqueFile = GetUniqueFilePath(outputFile);
            File.WriteAllBytes(uniqueFile, decompressedBytes);

            return uniqueFile;
        }}

        private static string ComputeMD5(string path)
        {{
            using var md5 = MD5.Create();
            byte[] hash = md5.ComputeHash(File.ReadAllBytes(path));
            return BitConverter.ToString(hash).Replace(`"-`", `"`").ToUpperInvariant();
        }}

        private static string GetUniqueFilePath(string path)
        {{
            if (!File.Exists(path))
                return path;

            string dir = Path.GetDirectoryName(path);
            string name = Path.GetFileNameWithoutExtension(path);
            string ext = Path.GetExtension(path);

            int counter = 1;
            string newPath;

            do
            {{
                newPath = Path.Combine(dir, `$`"{{name}}-{{counter}}{{ext}}`");
                counter++;
            }} while (File.Exists(newPath));

            return newPath;
        }}
    }}
}}

"@


function Invoke-EncodeBinary {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Path to the input binary file")]
        [string]$Path,

        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Directory where the output file is written")]
        [string]$Destination,
        [Parameter(Mandatory = $false, HelpMessage = "Max length of each Base64 chunk")]
        [ValidateRange(8,2Kb)]
        [int]$MaxChunkLength = 1Kb,
        [Parameter(Mandatory = $false, HelpMessage = "Name of the generated array variable")]
        [string]$ArrayName = "Base64Chunks",
        [Parameter(Mandatory = $false, HelpMessage = "only data, no decoding functions")]
        [switch]$OnlyData,
        [Parameter(Mandatory = $false, HelpMessage = "overwrite out file")]
        [switch]$Overwrite,
        [Parameter(Mandatory = $false, HelpMessage = "encode in dll or ps1")]
        [ValidateSet('dll','ps1')]
        [string]$Mode='ps1'
    )

    [bool]$IncludeDecodingFunctions = $True
    if($OnlyData){
        $IncludeDecodingFunctions = $False
    }

    [string]$ArrayNameHashVariable = "{0}_Hash" -f $ArrayName

    $FileItem = Get-Item -Path "$Path"
    $FileName = $FileItem.Name
    $FileBaseName = $FileItem.Basename
    $RecoveredFileName = Get-UniqueFilePath "`$ENV:Temp\recovered-$FileName"
    $Hash = (Get-FileHash -Path "$Path" -Algorithm MD5).Hash

    if(Test-Path "$Destination" -PathType Leaf){
        throw "`"$Destination`" is a file and already exists!"
    }elseif(-not(Test-Path "$Destination" -PathType Container)){
        Write-Verbose "Creating `"$Destination`""
        New-Item -Path "$Destination" -ItemType directory -Force -ErrorAction Ignore | Out-Null
    }

    $CsFileName = Join-Path "$ENV:Temp" "${FileBaseName}.cs"

    if($Mode -eq 'dll'){
      $OutFile = Join-Path $Destination "${FileBaseName}.dll"
    }else{
      $OutFile = Join-Path $Destination "${FileBaseName}.ps1"
    }

    if($Overwrite){
        Remove-Item -Path "$OutFile" -Force -ErrorAction Ignore | Out-Null
        Write-Verbose "Creating `"$OutFile`""
        New-Item -Path "$OutFile" -ItemType file -Force -ErrorAction Ignore | Out-Null
    }elseif(Test-Path "$OutFile" -PathType Leaf){
        throw "`"$OutFile`" already exists!"
    }

    # Read binary data
    Write-Verbose "Read binary data `"$Path`""
    $Bytes = [System.IO.File]::ReadAllBytes($Path)

    # Compress the byte array
    $MemoryStream = [System.IO.MemoryStream]::new()
    $GzipStream = [System.IO.Compression.GzipStream]::new($MemoryStream, [IO.Compression.CompressionMode]::Compress)
    $GzipStream.Write($Bytes, 0, $Bytes.Length)
    $GzipStream.Close()

    $CompressedBytes = $MemoryStream.ToArray()
    $MemoryStream.Dispose()

    # Convert to Base64 string
    $Base64String = [System.Convert]::ToBase64String($CompressedBytes)

    # Split into chunks
    $Chunks = @()
    for ($i = 0; $i -lt $Base64String.Length; $i += $MaxChunkLength) {
        $len = [math]::Min($MaxChunkLength, $Base64String.Length - $i)
        $Chunks += $Base64String.Substring($i, $len)
    }

    $AllChunks = $Chunks | % { "`"$_`"" }
    $PArt2 = [string]::Join("`,`n`t", $AllChunks)
    # Generate PowerShell code for array

    $csCodeFunction = @"

    string[] base64Chunks = new string[]
    {
        $PArt2
    };

    string hashExpected = "$Hash";
    string source = @"$Path";
    string recovered = Path.Combine(Path.GetTempPath(), "recovered-${FileName}");

"@ 

    $CsCode = $FileRestoreCs -f "RestoreFile${FileBaseName}","$csCodeFunction"

    $psCodeFunction = @"

function Get-${FileBaseName}EncodedData {
    [CmdletBinding()]
    param()`n

"@ 
    $psCode = $psCodeFunction

    $psCode += "`t`$${ArrayName} = @(" + $PArt2 + " )`n"

    $psCode += "`t`n#The hash of the binary file`n`t`$$ArrayNameHashVariable = `"$Hash`"`n"

    $psCode += @"

    [PsCustomObject]`$Ret = [PsCustomObject]@{
        Source = `"$Path`"
        Recovered = `"$RecoveredFileName`"
        Chunks = `$Base64Chunks
        Hash   = `$Base64Chunks_Hash
    }

    return `$Ret 
}

"@

    # Append function to reconstruct the file
    if($IncludeDecodingFunctions){
        $psCode += @"

function Restore-FromBase64Chunks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = `$true)]
        [string[]] `$Chunks,

        [Parameter(Mandatory = `$true)]
        [string] `$OutputFile
    )

    `$Base64 = `$Chunks -join ""
    [byte[]]`$CompressedBytes = [Convert]::FromBase64String(`$Base64)

    # Decompress
    `$InputStream = [System.IO.MemoryStream]::new(`$CompressedBytes)
    `$GzipStream = [System.IO.Compression.GzipStream]::new(`$InputStream, [IO.Compression.CompressionMode]::Decompress)
    `$OutputStream = [System.IO.MemoryStream]::new()
    `$Buffer = [byte[]]::new(4096)

    while (`$true) {
        `$read = `$GzipStream.Read(`$Buffer, 0, `$Buffer.Length)
        if (`$read -le 0) { break }
        `$OutputStream.Write(`$Buffer, 0, `$read)
    }

    `$GzipStream.Dispose()
    `$InputStream.Dispose()

    `$OutputBytes = `$OutputStream.ToArray()
    `$OutputStream.Dispose()
    `$realOutfile=Get-UniqueFilePath `$OutputFile
    [IO.File]::WriteAllBytes(`$realOutfile, `$OutputBytes)
    return `$realOutfile
}

function Restore-File${FileBaseName} {
    [CmdletBinding()]
    param ()

    [PsCustomObject]`$Data = Get-${FileBaseName}EncodedData
    `$fileChunks = `$Data.Chunks
    `$fileHash   = `$Data.Hash
    `$RecoveredFileName   = `$Data.Recovered


    
    `$outputFile=Restore-FromBase64Chunks -Chunks `$fileChunks -OutputFile `"`$RecoveredFileName`"
    `$RecoveredHash = (Get-FileHash -Path "`$outputFile" -Algorithm MD5).Hash

    if(`$RecoveredHash -ne `"`$fileHash`"){
        Write-Host "Invalid Hash!" -f DarkRed
        return `$Null
    }

    #Write-Host "File Recovered Successfully! `"`$outputFile`"" -f DarkGreen
    
    return `$outputFile
}

# Use 'Restore-FromBase64Chunks -Chunks `$${ArrayName} -OutputFile `"$RecoveredFileName`"' to restore the binary, or just plain 'Restore-FileFromChunks'

"@

    }

    if($Mode -eq 'dll'){
        Write-Host "Done. cs saved to `"$CsFileName`""
      Set-Content -Path "$CsFileName" -Value "$CsCode" -Encoding UTF8
      $CsCompiler = Join-Path "$ENV:VBCSCompilerPath" "csc.exe"
      &"$CsCompiler" '-target:library' "-out:$OutFile" "$CsFileName"
      $Log=@"
      Add-Type -Path "$OutFile"

      # Call the method
      `$filePath = [MyLibrary.MyFileRestorer]::RestoreFile${FileBaseName}();
"@
      Write-Host  $log
    }else{
      # Write to the output .ps1 file
      Set-Content -Path $OutFile -Value $psCode -Encoding UTF8
      Write-Host "Done. Script saved to $OutFile"
      Write-Host "Use Restore-FromBase64Chunks -Chunks `$${ArrayName} -OutputFile `"$RecoveredFileName`" to restore the binary, or just plain Restore-FileFromChunks" -f DarkCyan

    }
}



function Test-InvokeEncodeBinary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path="$PSScriptRoot\..\data\SkatesMov.mp4",
        [Parameter(Mandatory = $false, HelpMessage = "encode in dll or ps1")]
        [ValidateSet('dll','ps1')]
        [string]$Mode='ps1'
    )

    $outPath="$($PWD.Path)\$Mode"
    Invoke-EncodeBinary -Path $Path -Destination $outPath -MaxChunkLength 512  -Overwrite -Mode $Mode
}




