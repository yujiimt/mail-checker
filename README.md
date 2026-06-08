# inbox-watcher

複数の Gmail を横断してトリアージし、**新規の「要返信」メールだけ** Slack に通知する Claude Code 用スケルトン。
送信・自動返信はしない（読み取り + Slack 通知のみ）。

```
inbox-watcher/
├── inbox_watch.py            # cron 用ラッパー（claude -p → dedup → Slack）
├── prompts/triage.txt        # ヘッドレス用プロンプト（重要送信者をここで編集）
├── .claude/commands/inbox-triage.md  # 対話用 /inbox-triage コマンド
├── .env.example              # → .env にコピーして編集
├── crontab.example           # 1日数回の実行例
├── state/seen.json           # dedup 用（自動生成）
└── logs/                     # 実行ログ
```

## 動く仕組み
`claude -p` を非対話モードで叩いてトリアージ → 返ってきた JSON を `message_id` で既出除外 →
新規分だけ Slack に投稿 → 投稿済み ID を `state/seen.json` に追記。だから 1日数回回しても同じメールは鳴らない。

---

## あなた側で必要な手動セットアップ（4つ）

### 1. Gmail MCP（マルチアカウント対応）を入れる
Claude Code 標準の Google 連携は基本1アカウントなので、複数受信箱を見るなら **マルチアカウント対応の Gmail MCP** を使う。
コミュニティ製がいくつかある（いずれも自分の Google Cloud OAuth を使い、トークンはローカル保存）:
- coreyepstein/advanced-gmail-mcp … `accounts.json` に alias を列挙する方式
- chaymore/multi-google-mcp … 各ツールが `account` 引数を取る方式（Claude Code が案内付き install）
- 3vening/gmail-mcp … トークンを OS キーチェーンに保存

セットアップの勘所:
- Google Cloud Console でプロジェクト作成 → **Gmail API 有効化** → OAuth クライアント作成。
- OAuth 同意画面の **テストユーザー** に、監視したい全アドレスを追加（入れないとサインインが弾かれる）。
- アカウントごとに alias（例: `personal` / `gyoryu` / `tradefi`）を付け、**1アカウント＝1論理単位で分離**して登録する
  （まとめると別アカウントの結果が混ざる “account bleed” が起きやすい）。
- 設定先は Claude Code の `.mcp.json` または `~/.claude.json`。

### 2. ツール名を確認して `.env` に反映
入れた MCP が公開するツール名を確認し（`/mcp` や README で）、**読み取り系だけ**を `GMAIL_ALLOWED_TOOLS` に列挙する。
list/search/read/thread 相当だけ許可しておけば、ヘッドレスでも送信・削除は起きない。

### 3. Slack Incoming Webhook を作る
Slack で通知先チャンネル用の Incoming Webhook URL を発行し、`SLACK_WEBHOOK_URL` に入れる。
（`.env.example` を `.env` にコピーして両方の値を記入）

### 4. 除外リストを編集
`prompts/triage.txt` の「除外リスト」に、通知したくない送信者・ドメイン・件名キーワード
（ニュースレター / プロモ / 自動通知など）を追記する。重要送信者リストは使わない
（受信メールを判定軸で機械的にトリアージし、除外リストに該当するものだけ落とす方式）。

---

## 動作確認 → 自動化

```bash
# まず1回手動実行（Gmail のツール承認が出たら読み取り系だけ許可）
python3 inbox_watch.py
```

自動化（平日 9:00〜20:00 を 2時間ごと / 新規の要対応メールが無ければ通知しない）:

- **macOS / Linux**: `crontab.example` を参照して `crontab -e` に登録
- **Windows**: 同梱の `register-task.ps1` を実行してタスク スケジューラに登録
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\register-task.ps1
  ```
  解除は `Unregister-ScheduledTask -TaskName "inbox-watcher" -Confirm:$false`

## 注意
- このツールは **受信メールの確認のみ**。`GMAIL_ALLOWED_TOOLS` に読み取り系しか入れない限り、
  送信・下書き・既読化・削除は起きない。
- 新規（前回未通知）の要対応メールが無ければ Slack には通知されない（`state/seen.json` で dedup）。
- 2026/6/15 以降、サブスクプランの `claude -p`（Agent SDK）使用量は対話用とは別枠の月次クレジットを消費する。
  平日 数回/日 なら軽いが、頻度を上げるときはこの枠を意識する。
