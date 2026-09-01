[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$Path = "."
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Recursively merge one directory into another directory
# ------------------------------------------------------------

function Merge-FolderContents {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $items = Get-ChildItem -LiteralPath $Source -Force

    foreach ($item in $items) {
        $destinationItem = Join-Path $Destination $item.Name

        if ($item.PSIsContainer) {
            # If a folder with the same name already exists,
            # merge its contents instead of overwriting it.
            if (Test-Path -LiteralPath $destinationItem -PathType Container) {
                Merge-FolderContents `
                    -Source $item.FullName `
                    -Destination $destinationItem

                if ($PSCmdlet.ShouldProcess(
                    $item.FullName,
                    "Delete merged source folder"
                )) {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess(
                    $item.FullName,
                    "Move folder to $Destination"
                )) {
                    Move-Item `
                        -LiteralPath $item.FullName `
                        -Destination $Destination `
                        -Force
                }
            }
        }
        else {
            # Do not overwrite an existing file
            if (Test-Path -LiteralPath $destinationItem -PathType Leaf) {
                Write-Warning "File already exists. Skipping:"
                Write-Warning "  $destinationItem"
            }
            else {
                if ($PSCmdlet.ShouldProcess(
                    $item.FullName,
                    "Move file to $Destination"
                )) {
                    Move-Item `
                        -LiteralPath $item.FullName `
                        -Destination $Destination
                }
            }
        }
    }
}

# ------------------------------------------------------------
# Validate the supplied path
# ------------------------------------------------------------

$rootPath = (Resolve-Path -LiteralPath $Path).Path
$rootInfo = Get-Item -LiteralPath $rootPath

if (-not $rootInfo.PSIsContainer) {
    throw "The supplied path is not a folder: $rootPath"
}

Write-Host "Searching under:"
Write-Host "  $rootPath"

# ------------------------------------------------------------
# Find folders whose name is exactly the same as their parent
# ------------------------------------------------------------

$matchingFolders = Get-ChildItem `
    -LiteralPath $rootPath `
    -Directory `
    -Recurse `
    -Force |
    Where-Object {
        $_.Name -ceq $_.Parent.Name
    } |
    Sort-Object {
        $_.FullName.Length
    } -Descending

if (-not $matchingFolders) {
    Write-Host "No duplicate parent/child folder names were found."
    exit
}

Write-Host "`nMatching folders found:"
foreach ($folder in $matchingFolders) {
    Write-Host "  $($folder.Parent.FullName)\$($folder.Name)"
}

# ------------------------------------------------------------
# Process each duplicate folder
# ------------------------------------------------------------

foreach ($innerFolder in $matchingFolders) {
    if (-not (Test-Path -LiteralPath $innerFolder.FullName)) {
        continue
    }

    $outerFolder = $innerFolder.Parent.FullName

    Write-Host "`nProcessing:"
    Write-Host "  Source:      $($innerFolder.FullName)"
    Write-Host "  Destination: $outerFolder"

    try {
        Merge-FolderContents `
            -Source $innerFolder.FullName `
            -Destination $outerFolder

        # Delete the inner folder only after its contents have been moved
        $remainingItems = Get-ChildItem `
            -LiteralPath $innerFolder.FullName `
            -Force `
            -ErrorAction SilentlyContinue

        if (-not $remainingItems) {
            if ($PSCmdlet.ShouldProcess(
                $innerFolder.FullName,
                "Delete empty duplicate folder"
            )) {
                Remove-Item -LiteralPath $innerFolder.FullName -Force
                Write-Host "Deleted empty folder: $($innerFolder.FullName)" `
                    -ForegroundColor Green
            }
        }
        else {
            Write-Warning "Folder was not empty, so it was not deleted:"
            Write-Warning "  $($innerFolder.FullName)"
        }
    }
    catch {
        Write-Error "Failed to process '$($innerFolder.FullName)': $($_.Exception.Message)"
    }
}
