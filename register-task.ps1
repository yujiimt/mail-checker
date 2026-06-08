# register-task.ps1
# Register a Windows Scheduled Task that runs inbox_watch.py
# on weekdays every 2 hours from 09:00 to 20:00 (09,11,13,15,17,19).
#
# Usage (run inside the inbox-watcher folder):
#   powershell -ExecutionPolicy Bypass -File .\register-task.ps1
#
# Remove the task:
#   Unregister-ScheduledTask -TaskName "inbox-watcher" -Confirm:$false
# Run once manually:
#   Start-ScheduledTask -TaskName "inbox-watcher"
#
# NOTE: This file is intentionally ASCII-only to avoid PowerShell
# encoding issues with non-ASCII characters on Windows PowerShell 5.1.

$ErrorActionPreference = "Stop"

# Use this script's folder (= inbox-watcher) as the working directory
$WorkDir = $PSScriptRoot
if (-not $WorkDir) { $WorkDir = (Get-Location).Path }

# Resolve the python executable (full path preferred)
$Python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $Python) { $Python = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $Python) { throw "python not found. Please install Python 3." }

$TaskName = "inbox-watcher"

$Action = New-ScheduledTaskAction -Execute $Python -Argument "inbox_watch.py" -WorkingDirectory $WorkDir

# Weekday 09:00 trigger, then repeat every 2 hours for 11 hours
#   => runs at 09, 11, 13, 15, 17, 19 (last repetition by 20:00)
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 9:00am
$Trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 9:00am `
    -RepetitionInterval (New-TimeSpan -Hours 2) `
    -RepetitionDuration (New-TimeSpan -Hours 11)).Repetition

# Catch-up if missed / skip overlapping runs / 30 min limit per run
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
    -Description "Triage Gmail every 2h on weekdays 09-20 and notify Slack (new only)" -Force | Out-Null

Write-Host "[OK] Registered task '$TaskName'."
Write-Host "  Runs: weekdays at 09,11,13,15,17,19"
Write-Host "  WorkingDir: $WorkDir"
Write-Host "  python: $Python"
Write-Host ""
Write-Host "Check:  Get-ScheduledTask -TaskName $TaskName"
Write-Host "Test :  Start-ScheduledTask -TaskName $TaskName"
Write-Host "Remove: Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false"
