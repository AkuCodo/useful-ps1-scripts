param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Directory
)

# ============================================================
# Extract archives and delete them ONLY after successful
# extraction.
#
# Usage:
#
#   .\extract-and-delete-succesfull-files.ps1 .
#
#   .\extract-and-delete-succesfull-files.ps1 "D:\Archives"
#
# ============================================================

$ArchiveExtensions = @(
    ".zip",
    ".7z",
    ".rar",
    ".tar",
    ".gz",
    ".tgz",
    ".bz2",
    ".tbz",
    ".tbz2",
    ".xz",
    ".txz",
    ".z",
    ".lz",
    ".lzma",
    ".cab",
    ".arj",
    ".lzh",
    ".wim",
    ".cpio",
    ".deb",
    ".rpm"
)

# ------------------------------------------------------------
# Get actual filesystem path
# ------------------------------------------------------------

try {
    $Directory = [System.IO.Path]::GetFullPath($Directory)
}
catch {
    Write-Host ""
    Write-Host "ERROR: Invalid directory path:" -ForegroundColor Red
    Write-Host $Directory
    Write-Host ""
    exit 1
}

if (-not [System.IO.Directory]::Exists($Directory)) {
    Write-Host ""
    Write-Host "ERROR: Directory does not exist:" -ForegroundColor Red
    Write-Host $Directory
    Write-Host ""
    exit 1
}

# Make sure it is actually a directory
if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    Write-Host ""
    Write-Host "ERROR: Path is not a directory:" -ForegroundColor Red
    Write-Host $Directory
    Write-Host ""
    exit 1
}

# ------------------------------------------------------------
# Find 7-Zip
# ------------------------------------------------------------

$SevenZipCandidates = @(
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
)

$SevenZip = $SevenZipCandidates |
    Where-Object {
        Test-Path -LiteralPath $_
    } |
    Select-Object -First 1

if (-not $SevenZip) {
    Write-Host ""
    Write-Host "ERROR: 7-Zip was not found." -ForegroundColor Red
    Write-Host "Install 7-Zip and try again."
    Write-Host ""
    exit 1
}

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "           Archive Extractor" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Directory:"
Write-Host "  $Directory"
Write-Host ""
Write-Host "7-Zip:"
Write-Host "  $SevenZip"
Write-Host ""

# ------------------------------------------------------------
# Find archives
# ------------------------------------------------------------

$Files = @(Get-ChildItem -LiteralPath $Directory -File)

$Archives = @(
    $Files | Where-Object {
        $Extension = [System.IO.Path]::GetExtension($_.Name)

        $ArchiveExtensions -contains $Extension.ToLowerInvariant()
    }
)

if ($Archives.Count -eq 0) {

    Write-Host "No supported archives found." -ForegroundColor Yellow
    Write-Host ""

    exit 0
}

Write-Host "Found $($Archives.Count) archive(s)." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Process each archive
# ------------------------------------------------------------

foreach ($Archive in $Archives) {

    Write-Host "============================================" -ForegroundColor DarkGray
    Write-Host "Archive:" -ForegroundColor Cyan
    Write-Host "  $($Archive.Name)"
    Write-Host ""

    # --------------------------------------------------------
    # Determine extraction directory name
    # --------------------------------------------------------

    $FileName = $Archive.Name

    $CompoundExtensions = @(
        ".tar.gz",
        ".tar.bz2",
        ".tar.xz",
        ".tar.z",
        ".tgz",
        ".tbz",
        ".tbz2",
        ".txz"
    )

    $BaseName = $FileName
    $FoundCompoundExtension = $false

    foreach ($CompoundExtension in $CompoundExtensions) {

        if ($FileName.EndsWith(
            $CompoundExtension,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {

            $BaseName = $FileName.Substring(
                0,
                $FileName.Length - $CompoundExtension.Length
            )

            $FoundCompoundExtension = $true

            break
        }
    }

    if (-not $FoundCompoundExtension) {

        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
            $FileName
        )
    }

    # --------------------------------------------------------
    # Determine output directory
    # --------------------------------------------------------

    $ExtractDirectory = Join-Path `
        -Path $Directory `
        -ChildPath $BaseName

    # If the output directory already exists, don't overwrite it
    if (Test-Path -LiteralPath $ExtractDirectory) {

        $Counter = 1

        do {

            $ExtractDirectory = Join-Path `
                -Path $Directory `
                -ChildPath "${BaseName}_$Counter"

            $Counter++

        } while (Test-Path -LiteralPath $ExtractDirectory)
    }

    # --------------------------------------------------------
    # Create output directory
    # --------------------------------------------------------

    New-Item `
        -ItemType Directory `
        -Path $ExtractDirectory `
        -Force | Out-Null

    Write-Host "Extracting to:"
    Write-Host "  $ExtractDirectory"
    Write-Host ""

    # --------------------------------------------------------
    # Extract
    # --------------------------------------------------------

    & $SevenZip `
        x `
        $Archive.FullName `
        "-o$ExtractDirectory" `
        "-y"

    $ExitCode = $LASTEXITCODE

    # --------------------------------------------------------
    # Successful extraction
    # --------------------------------------------------------

    if ($ExitCode -eq 0) {

        Write-Host ""
        Write-Host "SUCCESS" -ForegroundColor Green
        Write-Host "Extraction completed successfully."
        Write-Host ""

        try {

            Remove-Item `
                -LiteralPath $Archive.FullName `
                -Force `
                -ErrorAction Stop

            Write-Host "Archive deleted:" -ForegroundColor Green
            Write-Host "  $($Archive.Name)"
        }
        catch {

            Write-Host "WARNING: Extraction succeeded but the archive" `
                "could not be deleted." -ForegroundColor Yellow

            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }

    # --------------------------------------------------------
    # Failed extraction
    # --------------------------------------------------------

    else {

        Write-Host ""
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "7-Zip exit code: $ExitCode"
        Write-Host ""
        Write-Host "Archive was NOT deleted." -ForegroundColor Yellow
        Write-Host ""

        # Delete output directory only if completely empty
        if (Test-Path -LiteralPath $ExtractDirectory) {

            $Contents = @(
                Get-ChildItem `
                    -LiteralPath $ExtractDirectory `
                    -Force `
                    -ErrorAction SilentlyContinue
            )

            if ($Contents.Count -eq 0) {

                Remove-Item `
                    -LiteralPath $ExtractDirectory `
                    -Force
            }
        }
    }

    Write-Host ""
}

# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Finished." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
