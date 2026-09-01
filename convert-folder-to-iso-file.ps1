[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",

    [switch]$Recurse,

    [switch]$DeleteSource
)

$ErrorActionPreference = "Stop"

# Locate oscdimg.exe
$oscdimg = Get-Command oscdimg.exe -ErrorAction SilentlyContinue

if (-not $oscdimg) {
    $possiblePaths = @(
        "$env:ProgramFiles(x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles(x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe"
    )

    foreach ($candidate in $possiblePaths) {
        if (Test-Path -LiteralPath $candidate) {
            $oscdimg = Get-Item -LiteralPath $candidate
            break
        }
    }
}

if (-not $oscdimg) {
    throw "oscdimg.exe was not found. Install the Windows ADK with Deployment Tools."
}

$rootPath = (Resolve-Path -LiteralPath $Path).Path
$rootInfo = Get-Item -LiteralPath $rootPath

if (-not $rootInfo.PSIsContainer) {
    throw "The specified path is not a folder: $rootPath"
}

# Only process folders directly inside the supplied path unless -Recurse is used
if ($Recurse) {
    $folders = Get-ChildItem -LiteralPath $rootPath -Directory -Recurse
}
else {
    $folders = Get-ChildItem -LiteralPath $rootPath -Directory
}

foreach ($folder in $folders) {
    $sourceFolder = $folder.FullName

    # Always place ISO outside the source folder
    $isoPath = Join-Path $rootPath "$($folder.Name).iso"

    # Safety check: never allow the ISO path inside the source folder
    $sourceUri = ([System.Uri]("$sourceFolder\")).AbsoluteUri
    $isoUri = ([System.Uri]$isoPath).AbsoluteUri

    if ($isoUri.StartsWith($sourceUri, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "Safety check failed. ISO would be inside source folder. Skipping: $sourceFolder"
        continue
    }

    if (Test-Path -LiteralPath $isoPath) {
        Write-Warning "ISO already exists. Skipping: $isoPath"
        continue
    }

    Write-Host "`nCreating ISO for: $sourceFolder"
    Write-Host "Output: $isoPath"

    try {
        & $oscdimg.Source -m -o -u2 $sourceFolder $isoPath

        if ($LASTEXITCODE -ne 0) {
            throw "oscdimg failed with exit code $LASTEXITCODE."
        }

        if (-not (Test-Path -LiteralPath $isoPath)) {
            throw "The ISO file was not created."
        }

        $isoInfo = Get-Item -LiteralPath $isoPath

        if ($isoInfo.Length -le 0) {
            throw "The ISO file is empty."
        }

        Write-Host "ISO created successfully: $isoPath" -ForegroundColor Green

        if ($DeleteSource) {
    		Remove-Item -LiteralPath $sourceFolder -Recurse -Force
    		Write-Host "Deleted source folder: $sourceFolder" -ForegroundColor Yellow
	}
	else {
    		Write-Host "Source folder kept. Use -DeleteSource to delete it automatically."
	}
    }
    catch {
        Write-Error "Conversion failed for '$sourceFolder': $($_.Exception.Message)"

        # Never remove the source folder after a failure
        if (Test-Path -LiteralPath $isoPath) {
            Write-Warning "An ISO exists, but the source folder was retained."
        }
    }
}
