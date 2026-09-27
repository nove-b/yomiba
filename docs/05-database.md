# データベース設計

## 方針

PostgreSQL を唯一の正本（source of truth）とする。Redis はキャッシュ・レート制限・
Streaming通知、Meilisearch は検索用の派生インデックスであり、永続データを置かない。

データは次の三つに分ける。

1. **ソーシャル**: アカウント、投稿、フォロー、リアクション、通知
2. **読書記録**: 作品・版、投稿への本の紐付け、ユーザーごとの読書状態
3. **連合**: リモートサーバー、ActivityPub活動、配送と受信の記録

リモートから取得したデータは変更・削除され得るキャッシュとして扱う。
自サーバーのユーザーが作ったデータと、リモート由来のデータを同じテーブルに持たせつつ、
`local` と ActivityPub の恒久URL（`uri`）で出所を区別する。

## 命名と共通カラム

- 主キーは内部用の `uuid` とする。
- 外部に公開する識別子は連番ではなく、UUIDv7 またはULIDから生成する。
- ActivityPub の識別子は `uri` に完全URLとして保存し、一意制約を付ける。
- ほぼ全テーブルに `created_at`、更新可能なものには `updated_at` を持たせる。
- 削除・連合上の Delete を受けた投稿は、即時物理削除せず `deleted_at` を設定する。
- 時刻はすべて `timestamptz`（UTC）で保存する。

## ソーシャル

### instances

既知のActivityPubサーバー。ローカルサーバー自身も1レコードとして持つ。

| カラム | 内容 |
| --- | --- |
| `id` | 内部ID |
| `domain` | 正規化済みドメイン。一意 |
| `actor_uri` | サーバーActorを持つ場合のURL |
| `software_name`, `software_version` | 検出できた実装情報 |
| `blocked_at`, `suspended_at` | 管理者による連合制限 |
| `last_fetched_at` | メタデータ最終取得時刻 |

### accounts

ローカル・リモートを問わないActor。

| カラム | 内容 |
| --- | --- |
| `id` | 内部ID |
| `instance_id` | 所属サーバー。ローカルアカウントもローカルinstanceを参照 |
| `username`, `domain` | `@user@domain` を構成する値 |
| `uri` | Actor URL。一意 |
| `inbox_uri`, `shared_inbox_uri`, `outbox_uri` | 連合先endpoint |
| `public_key_pem` | HTTP署名検証用公開鍵 |
| `display_name`, `note`, `avatar_url`, `header_url` | プロフィールのキャッシュ |
| `local`, `discoverable`, `suspended_at` | ローカル性・公開性・制限状態 |

Yomiba はパスワードを保存しない。ローカルアカウントのメールアドレスは公開プロフィールと
分離した `account_emails` に保存する。`email` は正規化して一意にし、`verified_at` により
所有確認済みかを管理する。

メール認証用の使い捨てトークンは `email_login_tokens` に保存する。トークンの平文は保存せず、
`token_digest`、`purpose`（`verify_email` / `sign_in`）、`expires_at`、`consumed_at` を持たせる。
メールのリンクを開いた時点でトークンを一度だけ消費し、期限切れ・使用済みのトークンは拒否する。

### follows

`follower_id` が `followee_id` をフォローする関係。承認待ちを扱うため `state`
（`pending` / `accepted` / `rejected`）を持つ。`(follower_id, followee_id)` は一意とする。

### statuses

通常投稿と本に紐付く投稿の共通本体。リモート投稿もここに正規化して保存する。

| カラム | 内容 |
| --- | --- |
| `id`, `uri` | 内部IDとActivityPub Object URL。一意 |
| `account_id` | 投稿者 |
| `in_reply_to_id`, `reblog_of_id` | 返信・ブーストの関係 |
| `content_html`, `content_text` | サニタイズ済みHTMLと検索・表示用プレーンテキスト |
| `visibility` | `public` / `unlisted` / `followers` / `direct` |
| `language`, `sensitive`, `spoiler_text` | 投稿属性 |
| `published_at`, `edited_at`, `deleted_at` | 投稿の時系列・削除状態 |
| `local` | 自サーバーで作成された投稿か |

メディアは `media_attachments`、ハッシュタグは `tags` と `status_tags`、メンションは
`status_mentions` として正規化する。

### reactions

絵文字リアクションを正規化する。Mastodon の Favourite / Like と、Misskey等の
EmojiReact を同じモデルで扱う。

| カラム | 内容 |
| --- | --- |
| `status_id`, `account_id` | 対象投稿とリアクションしたActor |
| `emoji` | Unicode絵文字または `:shortcode:` |
| `emoji_url` | カスタム絵文字画像のURL（任意） |
| `activity_uri` | 受信・送信したActivityのURL。重複排除に用いる |
| `local` | 自サーバー発か |

`(status_id, account_id, emoji)` を一意にし、同じユーザーが同じ投稿へ同一絵文字を
重複して付与できないようにする。

## 読書記録

### works と book_editions

「作品」と「本の版」を分ける。たとえば翻訳版・文庫版・電子版は同じ作品でも
ISBNや表紙、出版社、ページ数が異なるためである。**本の詳細ページの正規単位はISBNを
持つ版**とする。

`works` は作品の概念単位、`book_editions` は利用者が実際に読んだ版を表す。

| テーブル | 主なカラム |
| --- | --- |
| `works` | `id`, `canonical_title`, `original_language`, `description`, `cover_url` |
| `book_editions` | `id`, `work_id`, `title`, `subtitle`, `publisher`, `published_on`, `page_count`, `format`, `cover_url` |
| `book_identifiers` | `id`, `book_edition_id`, `scheme`, `value`。ISBN-10、ISBN-13、国会図書館IDなど |
| `contributors` | `id`, `name`, `sort_name`, `uri` |
| `book_contributors` | `book_edition_id`, `contributor_id`, `role`（author / translator / illustrator等） |

`book_identifiers` には `(scheme, value)` の一意制約を付ける。ISBN-10は可能であれば
ISBN-13へ正規化し、ISBN-13を詳細ページのURLと検索の主キーにする。ISBNがない同人誌や
古書も登録できるよう、IDの存在を必須にしないが、それらは安定した詳細ページURLを持たない
暫定版として扱う。重複候補の統合は、一般ユーザーではなく管理者向けの操作とする。

### status_books

投稿と本の版の紐付け。1投稿には複数冊を紐付けられる。

| カラム | 内容 |
| --- | --- |
| `status_id`, `book_edition_id` | 投稿と本の版 |
| `is_primary` | リアクションによる状態変更の対象となる本 |
| `source` | `user_selected` / `isbn_scan` / `imported` / `remote` |

`is_primary = true` の行が投稿ごとに最大1件となる部分一意インデックスを作る。
投稿に複数冊ある場合、絵文字リアクションによる読書状態の変更は主となる本だけに適用する。
これはActivityPubのリアクションが投稿全体を対象とし、投稿内のどの本へのリアクションかを
標準形式では示せないためである。

### user_books

ユーザーごとの現在の読書状態。投稿とは分離するため、投稿の削除や編集で読書状態を失わない。

| カラム | 内容 |
| --- | --- |
| `account_id`, `book_edition_id` | 誰の、どの版か。組み合わせで一意 |
| `state` | `want_to_read` / `reading` / `read` / `paused` / `dropped` |
| `started_on`, `finished_on` | 読み始め・読み終わりの日付（任意） |
| `rating` | 0.5〜5.0など。採用する場合のみ |
| `visibility` | 読書記録の公開範囲 |
| `state_changed_at` | 状態変更時刻 |

状態の変遷を残す必要があるため、更新時には `user_book_events` にも追記する。
ここには `from_state`、`to_state`、`source`（手動、投稿作成、絵文字リアクション、インポート）、
`status_id`、`reaction_id` を保存する。

### reaction_state_rules

リアクションと読書状態の対応は、サーバー共通の設定として管理する。

| カラム | 内容 |
| --- | --- |
| `emoji` | 対象のUnicodeまたはカスタム絵文字 |
| `target_state` | 遷移先の読書状態 |
| `enabled` | 有効・無効 |

この規則が適用されるのは、**リアクションした本人**の `user_books` だけとする。
他人の投稿へのリアクションで投稿者の読書状態を書き換えることはしない。
リアクション対象に `is_primary` の本がない場合は、状態を変更しない。
`user_books` と `user_book_events` はローカル情報であり、初期リリースではActivityPubに
直接配送しない。通常投稿と本に紐付いた投稿はいずれも `statuses` として連合し、
書誌の構造化データは本に紐付いた投稿にだけ付与する。

## 連合・配送

### federation_activities

受信・送信したActivityPub JSONの監査・重複排除用記録。
`activity_uri` を一意とし、`direction`（inbound / outbound）、`activity_type`、
`actor_uri`、`object_uri`、`payload`（JSONB）、`received_at` を保存する。

解析不能なpayloadは、サイズ上限と保存期間を設けた隔離テーブルに保存する。
アプリケーションの通常処理は、正規化済みの `accounts`、`statuses`、`reactions` を参照し、
毎回JSONを解析しない。

### delivery_attempts

Outbox配送の永続キュー。少なくとも `activity_id`、`inbox_uri`、`state`、`attempt_count`、
`next_attempt_at`、`last_error`、`delivered_at` を持つ。

ワーカーは `next_attempt_at` が到来したレコードをロックして取得し、指数バックオフで
再試行する。Webリクエスト内でリモートサーバーへ同期配送しない。

## インデックスと制約

- `accounts (username, domain)`、`accounts (uri)` は一意
- `statuses (uri)`、`federation_activities (activity_uri)` は一意
- タイムライン用: `statuses (account_id, published_at DESC)`、`statuses (published_at DESC) WHERE deleted_at IS NULL`
- 本の詳細用: `status_books (book_edition_id, status_id)` と `user_books (account_id, state)`
- 配送用: `delivery_attempts (state, next_attempt_at)`
- テキストの簡易検索には `statuses.content_text` と書誌のタイトル・著者に `pg_trgm` を使い、
Meilisearch障害時のフォールバックにする

## 最初に決めること

1. 本の詳細ページはISBN-13を正規キーとする。作品ページは将来の補助的な一覧として扱う。
2. 通常投稿と本に紐付く投稿は連合し、`user_books` と `user_book_events` はローカル情報とする。
3. 絵文字リアクションで状態を変えるのはリアクションした本人だけとする。
4. 1投稿には複数冊を紐付けられる。ただし状態遷移の対象は主となる1冊だけとする。
