[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$Path = "."
)

$ErrorActionPreference = "Stop"

# Resolve and validate the supplied path
$rootPath = (Resolve-Path -LiteralPath $Path).Path
$rootInfo = Get-Item -LiteralPath $rootPath

if (-not $rootInfo.PSIsContainer) {
    throw "The specified path is not a folder: $rootPath"
}

Write-Host "Scanning folder:"
Write-Host "  $rootPath"

# Only search for ISO files directly in the supplied folder.
# Files inside subfolders are ignored.
$isoFiles = Get-ChildItem `
    -LiteralPath $rootPath `
    -File `
    -Filter "*.iso" `
    -Force

if (-not $isoFiles) {
    Write-Host "No ISO files were found in the root of this folder."
    exit
}

foreach ($isoFile in $isoFiles) {
    $isoNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension(
        $isoFile.Name
    )

    $destinationFolder = Join-Path `
        -Path $rootPath `
        -ChildPath $isoNameWithoutExtension

    $destinationPath = Join-Path `
        -Path $destinationFolder `
        -ChildPath $isoFile.Name

    try {
        # Create a folder using the ISO filename without .iso
        if (-not (Test-Path -LiteralPath $destinationFolder)) {
            if ($PSCmdlet.ShouldProcess(
                $destinationFolder,
                "Create folder"
            )) {
                New-Item `
                    -Path $destinationFolder `
                    -ItemType Directory `
                    -Force | Out-Null
            }
        }

        # Avoid moving if the ISO is already in the correct folder
        if ($isoFile.Directory.FullName -eq $destinationFolder) {
            Write-Host "Already organized: $($isoFile.Name)"
            continue
        }

        # Do not overwrite an existing ISO
        if (Test-Path -LiteralPath $destinationPath) {
            Write-Warning "Destination ISO already exists. Skipping:"
            Write-Warning "  $destinationPath"
            continue
        }

        if ($PSCmdlet.ShouldProcess(
            $isoFile.FullName,
            "Move ISO to $destinationFolder"
        )) {
            Move-Item `
                -LiteralPath $isoFile.FullName `
                -Destination $destinationFolder

            Write-Host "Moved: $($isoFile.Name)" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to organize '$($isoFile.Name)': $($_.Exception.Message)"
    }
}
