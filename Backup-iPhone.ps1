# ============================================================
# iPhone -> H:\Poze\DCIM
#
# Incremental iPhone backup using Windows Shell / WPD
#
# Features:
#   - Recursively copies all folders and files
#   - Preserves folder structure
#   - Existing files are ALWAYS skipped
#   - Does NOT overwrite existing files
#   - Displays full destination path
#   - Waits for destination file to appear
#   - Detects completion when file size is stable
#   - Retries failed transfers
#   - Logs all operations
# ============================================================

$DestinationRoot = "H:\Poze\DCIM"

$MaxRetries = 3

# Maximum time to wait for one file
$TransferTimeoutMinutes = 10

# Consider a transfer complete when the destination
# file size has not changed for this many seconds.
$StableSecondsRequired = 5

$LogFile = Join-Path $DestinationRoot "iPhone-Backup.log"


# ============================================================
# Logging
# ============================================================

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"

    Write-Host $line -ForegroundColor $Color

    try {
        Add-Content `
            -LiteralPath $LogFile `
            -Value $line `
            -Encoding UTF8
    }
    catch {
        # Do not stop the backup if logging fails
    }
}


# ============================================================
# Create destination
# ============================================================

if (-not (Test-Path -LiteralPath $DestinationRoot)) {

    New-Item `
        -ItemType Directory `
        -Path $DestinationRoot `
        -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $LogFile)) {

    New-Item `
        -ItemType File `
        -Path $LogFile `
        -Force | Out-Null
}


# ============================================================
# Connect to Windows Shell
# ============================================================

Write-Log "Connecting to iPhone..." Cyan

$shell = New-Object -ComObject Shell.Application


# ============================================================
# Find This PC
# ============================================================

$thisPC = $shell.Namespace(17)

if (-not $thisPC) {
    throw "Could not access 'This PC'."
}


# ============================================================
# Find Apple iPhone
# ============================================================

$iphoneItem = $null

Write-Log "Looking for Apple iPhone..." Cyan

foreach ($item in $thisPC.Items()) {

    Write-Log "Device found: '$($item.Name)'" DarkGray

    if ($item.Name -eq "Apple iPhone") {
        $iphoneItem = $item
        break
    }
}

if (-not $iphoneItem) {

    Write-Log "Apple iPhone was not found." Red

    Write-Host ""
    Write-Host "Devices visible to Windows:" -ForegroundColor Yellow

    foreach ($item in $thisPC.Items()) {
        Write-Host "  $($item.Name)"
    }

    Write-Host ""
    Write-Host "Make sure the iPhone is:"
    Write-Host "  - connected by USB"
    Write-Host "  - unlocked"
    Write-Host "  - trusted by Windows"
    Write-Host ""

    exit 1
}

Write-Log "Found Apple iPhone." Green


# ============================================================
# Get iPhone folder
# ============================================================

$iphoneFolder = $iphoneItem.GetFolder

if (-not $iphoneFolder) {
    throw "Could not access Apple iPhone."
}


# ============================================================
# Find Internal Storage
# ============================================================

$internalStorageItem = $null

foreach ($item in $iphoneFolder.Items()) {

    Write-Log "iPhone item found: '$($item.Name)'" DarkGray

    if ($item.Name -eq "Internal Storage") {
        $internalStorageItem = $item
        break
    }
}

if (-not $internalStorageItem) {

    Write-Log "Could not find 'Internal Storage'." Red

    Write-Host ""
    Write-Host "Items visible under Apple iPhone:" -ForegroundColor Yellow

    foreach ($item in $iphoneFolder.Items()) {
        Write-Host "  $($item.Name)"
    }

    Write-Host ""

    exit 1
}

$internalStorage = $internalStorageItem.GetFolder

if (-not $internalStorage) {
    throw "Could not access 'Internal Storage'."
}

Write-Log "Accessing iPhone Internal Storage." Green


# ============================================================
# Wait for transfer completion
# ============================================================

function Wait-ForTransfer {

    param(
        [string]$Path
    )

    $deadline = (Get-Date).AddMinutes(
        $TransferTimeoutMinutes
    )

    $lastSize = -1
    $stableSince = $null
    $fileAppeared = $false

    while ((Get-Date) -lt $deadline) {

        if (Test-Path -LiteralPath $Path) {

            try {

                $file = Get-Item `
                    -LiteralPath $Path `
                    -ErrorAction Stop

                $size = [int64]$file.Length

                # ------------------------------------------------
                # First time we see the file
                # ------------------------------------------------

                if (-not $fileAppeared) {

                    $fileAppeared = $true
                    $lastSize = $size
                    $stableSince = Get-Date

                    Write-Host ""
                    Write-Host `
                        "    File appeared: $size bytes" `
                        -ForegroundColor DarkGray
                }

                # ------------------------------------------------
                # File size changed
                # ------------------------------------------------

                elseif ($size -ne $lastSize) {

                    $lastSize = $size
                    $stableSince = Get-Date

                    Write-Host `
                        "    Transfer: $size bytes" `
                        -ForegroundColor DarkGray
                }

                # ------------------------------------------------
                # File size unchanged
                # ------------------------------------------------

                else {

                    $stableSeconds = (
                        (Get-Date) - $stableSince
                    ).TotalSeconds

                    Write-Host `
                        "    File stable for $([int]$stableSeconds) seconds..." `
                        -ForegroundColor DarkGray

                    if ($stableSeconds -ge $StableSecondsRequired) {

                        Write-Host ""

                        return $true
                    }
                }

            }
            catch {
                # File may still be locked by Windows Shell
            }

        }
        else {

            Write-Host `
                "`r    Waiting for destination file..." `
                -NoNewline
        }

        Start-Sleep -Seconds 1
    }

    Write-Host ""

    return $false
}


# ============================================================
# Copy one file
# ============================================================

function Copy-iPhoneFile {

    param(
        $Item,
        [string]$DestinationFolder
    )

    $fileName = $Item.Name

    # Full destination path
    $destinationPath = Join-Path `
        $DestinationFolder `
        $fileName


    # ========================================================
    # Existing file = SKIP
    # ========================================================

    if (Test-Path -LiteralPath $destinationPath) {

        Write-Log `
            "SKIP: $destinationPath (already exists)" `
            DarkGray

        return "Skipped"
    }


    # ========================================================
    # Destination Shell folder
    # ========================================================

    $destinationShellFolder = $shell.Namespace(
        $DestinationFolder
    )

    if (-not $destinationShellFolder) {

        Write-Log `
            "Cannot access destination folder: $DestinationFolder" `
            Red

        return "Failed"
    }


    # ========================================================
    # Retry loop
    # ========================================================

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {

        Write-Log `
            "COPY [$attempt/$MaxRetries]: $destinationPath" `
            Cyan


        # ----------------------------------------------------
        # Make sure there isn't a stale destination file
        # ----------------------------------------------------

        if (Test-Path -LiteralPath $destinationPath) {

            Remove-Item `
                -LiteralPath $destinationPath `
                -Force `
                -ErrorAction SilentlyContinue
        }


        # ----------------------------------------------------
        # Start Windows Shell / MTP copy
        # ----------------------------------------------------

        try {

            # Windows Shell copy flags:
            #
            # 4    = FOF_SILENT
            # 16   = FOF_NOCONFIRMATION
            # 512  = FOF_NOCONFIRMMKDIR
            # 1024 = FOF_NOERRORUI
            #
            # 1556 = 4 + 16 + 512 + 1024

            $destinationShellFolder.CopyHere(
                $Item,
                1556
            )

        }
        catch {

            Write-Log `
                "Copy command failed: $($_.Exception.Message)" `
                Red

            Start-Sleep -Seconds 3

            continue
        }


        # ----------------------------------------------------
        # Wait for transfer to finish
        # ----------------------------------------------------

        $success = Wait-ForTransfer `
            -Path $destinationPath


        if ($success) {

            Write-Log `
                "OK: $destinationPath" `
                Green

            return "Copied"
        }


        # ----------------------------------------------------
        # Transfer timed out
        # ----------------------------------------------------

        Write-Log `
            "TIMEOUT: $destinationPath" `
            Yellow


        # ----------------------------------------------------
        # Retry
        # ----------------------------------------------------

        if ($attempt -lt $MaxRetries) {

            Write-Log `
                "Retrying: $destinationPath" `
                Yellow

            if (Test-Path -LiteralPath $destinationPath) {

                Remove-Item `
                    -LiteralPath $destinationPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }

            Start-Sleep -Seconds 3
        }
    }


    # ========================================================
    # Failed
    # ========================================================

    Write-Log `
        "FAILED after $MaxRetries attempts: $destinationPath" `
        Red

    return "Failed"
}


# ============================================================
# Statistics
# ============================================================

$Statistics = @{
    Copied  = 0
    Skipped = 0
    Failed  = 0
}


# ============================================================
# Recursive folder processing
# ============================================================

function Process-iPhoneFolder {

    param(
        $SourceFolder,
        [string]$DestinationPath
    )


    # --------------------------------------------------------
    # Create destination folder
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $DestinationPath)) {

        New-Item `
            -ItemType Directory `
            -Path $DestinationPath `
            -Force | Out-Null
    }


    # --------------------------------------------------------
    # Process all items
    # --------------------------------------------------------

    foreach ($item in $SourceFolder.Items()) {

        if ($item.IsFolder) {

            $folderName = $item.Name

            Write-Log `
                "FOLDER: $folderName" `
                Magenta

            $subDestination = Join-Path `
                $DestinationPath `
                $folderName

            try {

                $subFolder = $item.GetFolder

                if ($subFolder) {

                    Process-iPhoneFolder `
                        -SourceFolder $subFolder `
                        -DestinationPath $subDestination
                }
                else {

                    Write-Log `
                        "Could not access folder: $folderName" `
                        Red
                }

            }
            catch {

                Write-Log `
                    "ERROR accessing folder '$folderName': $($_.Exception.Message)" `
                    Red
            }

        }
        else {

            $result = Copy-iPhoneFile `
                -Item $item `
                -DestinationFolder $DestinationPath

            $Statistics[$result]++
        }
    }
}


# ============================================================
# START
# ============================================================

$startTime = Get-Date

Write-Log ""
Write-Log "============================================================" Cyan
Write-Log "iPhone backup started" Cyan
Write-Log "============================================================" Cyan
Write-Log "Source      : This PC\Apple iPhone\Internal Storage"
Write-Log "Destination : $DestinationRoot"
Write-Log "Max retries : $MaxRetries"
Write-Log "Started     : $startTime"
Write-Log ""


# ============================================================
# Process everything
# ============================================================

Process-iPhoneFolder `
    -SourceFolder $internalStorage `
    -DestinationPath $DestinationRoot


# ============================================================
# SUMMARY
# ============================================================

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Log ""
Write-Log "============================================================" Cyan
Write-Log "BACKUP FINISHED" Green
Write-Log "============================================================" Cyan

Write-Log "Copied   : $($Statistics.Copied)" Green
Write-Log "Skipped  : $($Statistics.Skipped)" DarkGray
Write-Log "Failed   : $($Statistics.Failed)" Red
Write-Log "Duration : $duration"
Write-Log "Log      : $LogFile"

Write-Host ""
Write-Host "============================================================"
Write-Host "Backup finished."
Write-Host ""
Write-Host "Copied   : $($Statistics.Copied)"
Write-Host "Skipped  : $($Statistics.Skipped)"
Write-Host "Failed   : $($Statistics.Failed)"
Write-Host ""
Write-Host "Log:"
Write-Host $LogFile
Write-Host "============================================================"