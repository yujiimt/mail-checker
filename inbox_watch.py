#!/usr/bin/env python3
"""
inbox_watch.py
複数 Gmail を横断トリアージし、新規の「要返信」メールだけ Slack に通知する。
cron から呼ばれる想定。送信・自動返信は一切しない（読み取り + Slack 通知のみ）。

フロー:
  1. claude -p でトリアージ（Gmail MCP のツールを使用）→ JSON を受け取る
  2. message_id で既出を除外（state/seen.json）
  3. 新規分だけ Slack Incoming Webhook に投稿
  4. 投稿できた message_id を seen に追記
"""
import json
import os
import sys
import pathlib
import shutil
import subprocess
import urllib.request

BASE = pathlib.Path(__file__).resolve().parent
SEEN_FILE = BASE / "state" / "seen.json"
PROMPT_FILE = BASE / "prompts" / "triage.txt"


def load_env():
    """同ディレクトリに .env があれば読み込む（cron は環境変数が薄いため）。"""
    envf = BASE / ".env"
    if envf.exists():
        for line in envf.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def load_seen():
    try:
        return set(json.loads(SEEN_FILE.read_text(encoding="utf-8")))
    except (FileNotFoundError, json.JSONDecodeError):
        return set()


def save_seen(seen):
    SEEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    # 肥大化防止: 直近 2000 件だけ保持
    SEEN_FILE.write_text(json.dumps(sorted(seen)[-2000:], ensure_ascii=False), encoding="utf-8")


def run_claude(prompt):
    # ★ 読み取り系ツールだけを許可（送信・下書き・削除系は入れない）。
    # 既定値は advanced-gmail-mcp の読み取り系ツール名。別の MCP を使う場合は .env で上書き。
    allowed = os.environ.get(
        "GMAIL_ALLOWED_TOOLS",
        "mcp__gmail__list_emails,mcp__gmail__search_emails,mcp__gmail__read_email,mcp__gmail__get_thread,mcp__gmail__get_labels",
    )
    # claude 実行ファイルを解決。Windows では npm 製の claude が claude.cmd のため、
    # フルパス解決 + シェル経由で起動しないと FileNotFoundError(WinError 2) になる。
    claude_exe = shutil.which("claude")
    if not claude_exe:
        sys.stderr.write(
            "claude コマンドが見つかりません。Claude Code CLI をインストールし、PATH を通してください。\n"
            "（タスクスケジューラ実行時は PATH が薄いことがあるので、その場合は claude のフルパス指定が必要）\n"
        )
        sys.exit(127)
    cmd = [claude_exe, "-p", "--output-format", "json", "--allowedTools", allowed]
    # プロンプトは引数ではなく stdin で渡す（長文・改行・引用符のクォート崩れを回避）。
    proc = subprocess.run(
        cmd,
        input=prompt,
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=str(BASE),
        shell=(os.name == "nt"),
    )
    if proc.returncode != 0:
        sys.stderr.write("claude failed:\n" + proc.stderr + "\n")
        sys.exit(proc.returncode)
    payload = json.loads(proc.stdout)
    text = payload.get("result", "").strip()
    # 念のためコードフェンスを除去
    if text.startswith("```"):
        text = text.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    return json.loads(text)


def fmt_item(i):
    subj = i.get("subject", "(件名なし)")
    link = i.get("gmail_link") or ""
    head = f"<{link}|{subj}>" if link else subj
    return (
        f"• [{i.get('account', '?')}] {head}\n"
        f"    from: {i.get('from', '?')} ・ {i.get('received', '')}\n"
        f"    → {i.get('reason', '')}"
    )


def post_slack(new_items, total_needs):
    webhook = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook:
        sys.stderr.write("SLACK_WEBHOOK_URL が未設定です\n")
        sys.exit(1)
    if not new_items:
        return False
    high = [i for i in new_items if i.get("priority") == "high"]
    mid = [i for i in new_items if i.get("priority") != "high"]
    lines = [f"*📥 受信トレイ・トリアージ*  （新規 {len(new_items)} 件 / 現在の要返信 計 {total_needs} 件）", ""]
    if high:
        lines.append("*🔴 優先*")
        lines += [fmt_item(i) for i in high]
        lines.append("")
    if mid:
        lines.append("*🟡 通常*")
        lines += [fmt_item(i) for i in mid]
    payload = {"text": "\n".join(lines)}
    req = urllib.request.Request(
        webhook, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=15)
    return True


def main():
    load_env()
    prompt = PROMPT_FILE.read_text(encoding="utf-8")
    data = run_claude(prompt)
    items = [i for i in data.get("items", []) if i.get("needs_reply") and i.get("message_id")]
    seen = load_seen()
    new_items = [i for i in items if i["message_id"] not in seen]
    if post_slack(new_items, len(items)):
        for i in new_items:
            seen.add(i["message_id"])
        save_seen(seen)
        print(f"posted {len(new_items)} new item(s)")
    else:
        print("no new items")


if __name__ == "__main__":
    main()
