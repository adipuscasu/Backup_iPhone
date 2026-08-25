# Backup_iPhone

A PowerShell script that performs an **incremental backup of an iPhone's photo & video library** (`DCIM`) to a local folder on a Windows PC. It uses the Windows Shell (WPD / MTP) to copy files the same way Explorer does, so it works with any iPhone that Windows can see — no extra drivers, no iTunes, no dependencies.

## What it does

- Recursively copies **all folders and files** from `This PC \ Apple iPhone \ Internal Storage`.
- **Preserves the folder structure** on the destination.
- **Skips files that already exist** — it never overwrites an existing file, so every run only transfers new media (true incremental behavior).
- **Waits for each file to finish transferring** by watching the destination file size until it stops growing.
- **Retries** a file if the transfer times out or fails.
- **Logs every operation** to the console and to a log file.
- Prints a **summary** at the end (copied / skipped / failed, total duration).

## Requirements

- **Windows** (uses the `Shell.Application` COM object).
- An iPhone that Windows can see in **File Explorer** under *This PC*.
- No other dependencies.

Before running, make sure the iPhone is:

- Connected by **USB**,
- **Unlocked**,
- **Trusted by Windows** (tap *Trust this computer* when prompted).

## Usage

1. Connect the iPhone to your PC and make sure it is unlocked and trusted.
2. Open a PowerShell terminal and run the script:

   ```powershell
   .\Backup-iPhone.ps1
   ```

   > If PowerShell blocks script execution, allow it first:
   >
   > ```powershell
   > Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   > ```

3. Wait for the run to finish. You'll see a summary like:

   ```
   Copied   : 12
   Skipped  : 348
   Failed   : 0
   Duration : 00:04:12
   Log      : H:\Poze\DCIM\iPhone-Backup.log
   ```

The destination folder and the log file are created automatically if they don't already exist.

## Configuration

All settings are defined near the top of `Backup-iPhone.ps1` and can be edited to suit your setup:

| Variable                   | Default             | Description                                                        |
| -------------------------- | ------------------- | ------------------------------------------------------------------ |
| `$DestinationRoot`         | `H:\Poze\DCIM`      | Where the iPhone files are copied.                                  |
| `$MaxRetries`              | `3`                 | How many times a single file transfer is retried before giving up.  |
| `$TransferTimeoutMinutes`  | `10`                | Max time to wait for one file to finish transferring.               |
| `$StableSecondsRequired`   | `5`                 | Seconds the file size must be unchanged before it's considered done. |
| `$LogFile`                 | `<destination>\iPhone-Backup.log` | Log file (created inside `$DestinationRoot`).            |

To change where your photos are saved, edit `$DestinationRoot` to any folder path you like.

## How it detects a finished transfer

Copying a large video over MTP can take a while, and the Windows Shell does not report when a copy is complete. The script solves this by polling the **destination** file: it watches the file size once per second and considers the transfer finished once the size has not changed for `$StableSecondsRequired` seconds. If the deadline (`$TransferTimeoutMinutes`) is reached first, the file is retried up to `$MaxRetries` times.

## Troubleshooting

- **"Apple iPhone was not found."** — Windows does not see the phone. Check the USB cable, unlock the phone, tap *Trust*, and confirm it appears under *This PC* in File Explorer. The script lists the devices it can see to help diagnose this.
- **"Could not find 'Internal Storage'."** — The phone is visible but its storage isn't exposed. Reconnect the device; the script lists the items it found under *Apple iPhone*.
- **Some files FAILED** — Check the log file for the specific files and timestamps, then re-run the script. Because existing files are skipped, a re-run only retries what's still missing.

## Log file

Every run appends timestamped entries to the log file (by default `iPhone-Backup.log` inside the destination folder), including device discovery, per-file `COPY`/`SKIP`/`OK`/`TIMEOUT`/`FAILED` events, and the final summary.

## License

Distributed under the **MIT License** — see the [`LICENSE`](LICENSE) file for details.
