param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Directory
)

# ============================================================
# Recursive Archive Extractor
#
# - Finds archives recursively from the supplied directory
# - Extracts archives
# - Deletes archives ONLY after successful extraction
# - Searches extracted contents for more archives
# - Continues until no archives remain
#
# Usage:
#
#   .\extract-and-delete-succesfull-files.ps1 .
#
#   .\extract-and-delete-succesfull-files.ps1 "D:\Archives"
#
# Requires 7-Zip
# ============================================================


# ------------------------------------------------------------
# Supported archive extensions
# ------------------------------------------------------------

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
    ".zst",

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
# Compound extensions
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Convert supplied path to absolute filesystem path
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


# ------------------------------------------------------------
# Verify directory exists
# ------------------------------------------------------------

if (-not [System.IO.Directory]::Exists($Directory)) {

    Write-Host ""
    Write-Host "ERROR: Directory does not exist:" -ForegroundColor Red
    Write-Host $Directory
    Write-Host ""

    exit 1
}


# ------------------------------------------------------------
# Verify it is a directory
# ------------------------------------------------------------

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


# ============================================================
# Statistics
# ============================================================

$TotalProcessed = 0
$TotalSuccessful = 0
$TotalFailed = 0
$TotalDeleted = 0


# ============================================================
# Function: Determine whether a file is an archive
# ============================================================

function Test-IsArchive {

    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $Extension = [System.IO.Path]::GetExtension(
        $File.Name
    ).ToLowerInvariant()

    return ($ArchiveExtensions -contains $Extension)
}


# ============================================================
# Function: Get archive base name
# ============================================================

function Get-ArchiveBaseName {

    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Archive
    )

    $FileName = $Archive.Name


    # Check compound extensions first
    foreach ($CompoundExtension in $CompoundExtensions) {

        if (
            $FileName.EndsWith(
                $CompoundExtension,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {

            return $FileName.Substring(
                0,
                $FileName.Length - $CompoundExtension.Length
            )
        }
    }


    # Normal extension
    return [System.IO.Path]::GetFileNameWithoutExtension(
        $FileName
    )
}


# ============================================================
# Function: Get unique extraction directory
# ============================================================

function Get-ExtractionDirectory {

    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Archive
    )

    $BaseName = Get-ArchiveBaseName -Archive $Archive

    $ExtractDirectory = Join-Path `
        -Path $Archive.DirectoryName `
        -ChildPath $BaseName


    # If directory doesn't exist, use it
    if (
        -not [System.IO.Directory]::Exists(
            $ExtractDirectory
        )
    ) {

        return $ExtractDirectory
    }


    # Directory already exists
    $Counter = 1

    do {

        $ExtractDirectory = Join-Path `
            -Path $Archive.DirectoryName `
            -ChildPath "${BaseName}_$Counter"

        $Counter++

    }
    while (
        [System.IO.Directory]::Exists(
            $ExtractDirectory
        )
    )


    return $ExtractDirectory
}


# ============================================================
# Function: Extract one archive
# ============================================================

function Expand-OneArchive {

    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Archive
    )


    # --------------------------------------------------------
    # Verify archive still exists
    # --------------------------------------------------------

    if (
        -not [System.IO.File]::Exists(
            $Archive.FullName
        )
    ) {

        return
    }


    $script:TotalProcessed++


    Write-Host ""
    Write-Host "============================================" `
        -ForegroundColor DarkGray

    Write-Host "ARCHIVE:" -ForegroundColor Cyan
    Write-Host "  $($Archive.FullName)"

    Write-Host ""


    # --------------------------------------------------------
    # Determine extraction directory
    # --------------------------------------------------------

    $ExtractDirectory = Get-ExtractionDirectory `
        -Archive $Archive


    # --------------------------------------------------------
    # Create extraction directory
    # --------------------------------------------------------

    try {

        New-Item `
            -ItemType Directory `
            -Path $ExtractDirectory `
            -Force `
            -ErrorAction Stop | Out-Null

    }
    catch {

        Write-Host "FAILED TO CREATE OUTPUT DIRECTORY" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        $script:TotalFailed++

        return
    }


    Write-Host "Extracting to:" -ForegroundColor Yellow
    Write-Host "  $ExtractDirectory"

    Write-Host ""


    # --------------------------------------------------------
    # Extract with 7-Zip
    # --------------------------------------------------------

    & $SevenZip `
        x `
        $Archive.FullName `
        "-o$ExtractDirectory" `
        "-y"


    $ExitCode = $LASTEXITCODE


    # --------------------------------------------------------
    # SUCCESS
    # --------------------------------------------------------

    if ($ExitCode -eq 0) {

        $script:TotalSuccessful++


        Write-Host ""
        Write-Host "SUCCESS" -ForegroundColor Green

        Write-Host "  Extraction completed successfully."


        # ----------------------------------------------------
        # Delete original archive
        # ----------------------------------------------------

        try {

            Remove-Item `
                -LiteralPath $Archive.FullName `
                -Force `
                -ErrorAction Stop

            $script:TotalDeleted++


            Write-Host ""
            Write-Host "DELETED:" -ForegroundColor Green
            Write-Host "  $($Archive.Name)"

        }
        catch {

            Write-Host ""
            Write-Host "WARNING:" -ForegroundColor Yellow

            Write-Host "Extraction succeeded, but the archive"
            Write-Host "could not be deleted."

            Write-Host ""
            Write-Host $_.Exception.Message `
                -ForegroundColor Yellow
        }


        # ----------------------------------------------------
        # Find nested archives
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "Searching for nested archives..." `
            -ForegroundColor Cyan


        $NestedFiles = @(
            Get-ChildItem `
                -LiteralPath $ExtractDirectory `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue
        )


        $NestedArchives = @(
            $NestedFiles |
            Where-Object {
                Test-IsArchive -File $_
            }
        )


        if ($NestedArchives.Count -gt 0) {

            Write-Host ""
            Write-Host "Found $($NestedArchives.Count) nested archive(s)." `
                -ForegroundColor Cyan


            foreach ($NestedArchive in $NestedArchives) {

                if (
                    [System.IO.File]::Exists(
                        $NestedArchive.FullName
                    )
                ) {

                    Expand-OneArchive `
                        -Archive $NestedArchive
                }
            }

        }
        else {

            Write-Host ""
            Write-Host "No nested archives found." `
                -ForegroundColor DarkGray
        }
    }


    # --------------------------------------------------------
    # FAILURE
    # --------------------------------------------------------

    else {

        $script:TotalFailed++


        Write-Host ""
        Write-Host "FAILED" -ForegroundColor Red

        Write-Host "  Archive: $($Archive.Name)"
        Write-Host "  7-Zip exit code: $ExitCode"

        Write-Host ""
        Write-Host "Archive was NOT deleted." `
            -ForegroundColor Yellow


        # ----------------------------------------------------
        # Remove output directory if empty
        # ----------------------------------------------------

        if (
            [System.IO.Directory]::Exists(
                $ExtractDirectory
            )
        ) {

            $Contents = @(
                Get-ChildItem `
                    -LiteralPath $ExtractDirectory `
                    -Force `
                    -ErrorAction SilentlyContinue
            )


            if ($Contents.Count -eq 0) {

                Remove-Item `
                    -LiteralPath $ExtractDirectory `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }
}


# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "============================================" `
    -ForegroundColor Cyan

Write-Host "       RECURSIVE ARCHIVE EXTRACTOR" `
    -ForegroundColor Cyan

Write-Host "============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Directory:"
Write-Host "  $Directory"

Write-Host ""

Write-Host "7-Zip:"
Write-Host "  $SevenZip"

Write-Host ""


# ============================================================
# Find INITIAL archives recursively
# ============================================================

$Files = @(
    Get-ChildItem `
        -LiteralPath $Directory `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)


$Archives = @(
    $Files |
    Where-Object {
        Test-IsArchive -File $_
    }
)


# ============================================================
# Nothing found
# ============================================================

if ($Archives.Count -eq 0) {

    Write-Host "No supported archives found." `
        -ForegroundColor Yellow

    Write-Host ""

    exit 0
}


# ============================================================
# Initial archive count
# ============================================================

Write-Host "Found $($Archives.Count) archive(s)." `
    -ForegroundColor Green

Write-Host ""


# ============================================================
# Process INITIAL archives
# ============================================================

foreach ($Archive in $Archives) {

    # The archive might have already been deleted because
    # another archive operation processed it.

    if (
        [System.IO.File]::Exists(
            $Archive.FullName
        )
    ) {

        Expand-OneArchive `
            -Archive $Archive
    }
}


# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host ""
Write-Host "============================================" `
    -ForegroundColor Cyan

Write-Host "                 FINISHED" `
    -ForegroundColor Green

Write-Host "============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Archives processed:       $TotalProcessed"

Write-Host "Successful extractions:   $TotalSuccessful" `
    -ForegroundColor Green

Write-Host "Archives deleted:         $TotalDeleted" `
    -ForegroundColor Green

Write-Host "Failed extractions:       $TotalFailed" `
    -ForegroundColor Red

Write-Host ""

Write-Host "============================================" `
    -ForegroundColor Cyan
