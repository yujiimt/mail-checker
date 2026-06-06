# register-task.ps1
# 平日 9:00〜20:00 を 2時間ごと（9, 11, 13, 15, 17, 19 時）に inbox_watch.py を実行する
# Windows タスク スケジューラのタスクを登録する。
#
# 使い方: inbox-watcher フォルダ内で PowerShell を開き、次を実行
#   powershell -ExecutionPolicy Bypass -File .\register-task.ps1
#
# 解除したいときは:
#   Unregister-ScheduledTask -TaskName "inbox-watcher" -Confirm:$false
# 手動で1回テスト実行:
#   Start-ScheduledTask -TaskName "inbox-watcher"

$ErrorActionPreference = "Stop"

# このスクリプトがあるフォルダ（= inbox-watcher）を作業ディレクトリにする
$WorkDir = $PSScriptRoot
if (-not $WorkDir) { $WorkDir = (Get-Location).Path }

# python の実行ファイルを解決（フルパス推奨）
$Python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $Python) { $Python = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $Python) { throw "python が見つかりません。Python 3 をインストールしてください。" }

$TaskName = "inbox-watcher"

$Action = New-ScheduledTaskAction -Execute $Python -Argument "inbox_watch.py" -WorkingDirectory $WorkDir

# 平日 9:00 開始のトリガーに、「2時間ごとに11時間繰り返す」設定を付ける
#   → 9, 11, 13, 15, 17, 19 時に実行（最後の繰り返しが 20:00 まで）
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 9:00am
$Trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 9:00am `
    -RepetitionInterval (New-TimeSpan -Hours 2) `
    -RepetitionDuration (New-TimeSpan -Hours 11)).Repetition

# 取りこぼし時は起動可能になったら実行 / 多重起動はスキップ / 1回の上限30分
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
    -Description "平日 9-20時を2時間ごとに Gmail をトリアージして Slack 通知（新規のみ）" -Force | Out-Null

Write-Host "[OK] タスク '$TaskName' を登録しました。"
Write-Host "  実行: 平日 9,11,13,15,17,19 時"
Write-Host "  作業フォルダ: $WorkDir"
Write-Host "  python: $Python"
Write-Host ""
Write-Host "確認:   Get-ScheduledTask -TaskName $TaskName"
Write-Host "手動テスト: Start-ScheduledTask -TaskName $TaskName"
Write-Host "解除:   Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false"
