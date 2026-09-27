# API設計

## 共通仕様

- APIの基底パスは `/api/v1` とする。Mastodon互換の既存パス・JSON形式は可能な限り維持する。
- 認証が必要なエンドポイントは OAuth 2.0 Bearer Token を `Authorization` ヘッダーで受け取る。
- 日時は ISO 8601 UTC、IDは外部公開用のUUIDv7またはULID文字列を返す。
- 一覧は `limit`（既定20、最大40）、`max_id`、`since_id`、`min_id` によるカーソルページングを使う。
- 作成・更新に失敗した場合は `application/problem+json` を返す。`type`、`title`、`status`、`detail`、
  必要に応じてフィールド別の `errors` を含める。
- 公開範囲は `public` / `unlisted` / `followers` / `direct` とする。

## 認証・アカウント

Mastodon互換クライアントを接続するために、少なくとも次を実装する。
Yomiba はパスワードログインを提供せず、登録済みメールアドレスへ送る使い捨ての
認証リンク（マジックリンク）でログインする。

| Method | Path | 認証 | 用途 |
| --- | --- | --- | --- |
| `POST` | `/api/v1/accounts` | 不要 | ユーザー名とメールアドレスでアカウントを仮登録し、確認メールを送る |
| `POST` | `/api/v1/auth/email/request` | 不要 | ログイン用またはメール確認用の認証リンクを送る |
| `POST` | `/api/v1/auth/email/verify` | 不要 | メールの認証トークンを一度だけ消費し、Webセッションを開始する |
| `POST` | `/api/v1/apps` | 不要 | OAuthクライアントを登録する |
| `POST` | `/oauth/token` | 不要 | アクセストークンを発行・更新する |
| `GET` | `/api/v1/accounts/verify_credentials` | 必須 | ログイン中のアカウントを取得する |
| `GET` | `/api/v1/accounts/:id` | 任意 | プロフィールを取得する |
| `GET` | `/api/v1/accounts/:id/statuses` | 任意 | アカウントの投稿一覧を取得する |
| `POST` | `/api/v1/accounts/:id/follow` | 必須 | フォローする |
| `POST` | `/api/v1/accounts/:id/unfollow` | 必須 | フォローを解除する |
| `GET` | `/api/v1/notifications` | 必須 | 通知一覧を取得する |

`POST /api/v1/auth/email/request` は `{ "email": "reader@example.com", "purpose": "sign_in" }`
を受け取る。アカウントの有無を推測されないよう、未登録・未確認のメールアドレスにも同じ
`202 Accepted` を返す。送信頻度はメールアドレス・IPアドレスごとに制限する。

メールのリンクには短い有効期限を持つ使い捨てトークンを含める。Web画面はトークンを
`POST /api/v1/auth/email/verify` へ渡し、成功時に安全なHTTP-onlyセッションCookieを受け取る。
OAuthクライアントは、そのWebセッションで認可コードを発行し、従来どおり `/oauth/token` で
Bearer Tokenへ交換する。トークンの平文とパスワードはいずれもDBへ保存しない。

## 投稿・リアクション

### 投稿

| Method | Path | 認証 | 用途 |
| --- | --- | --- | --- |
| `POST` | `/api/v1/statuses` | 必須 | 通常投稿または本に紐付く投稿を作成する |
| `GET` | `/api/v1/statuses/:id` | 任意 | 投稿を取得する |
| `PUT` | `/api/v1/statuses/:id` | 必須 | 自分の投稿を編集する |
| `DELETE` | `/api/v1/statuses/:id` | 必須 | 自分の投稿を削除する |
| `GET` | `/api/v1/statuses/:id/context` | 任意 | 返信スレッドを取得する |
| `POST` | `/api/v1/statuses/:id/favourite` | 必須 | お気に入りを付与する |
| `POST` | `/api/v1/statuses/:id/unfavourite` | 必須 | お気に入りを解除する |
| `POST` | `/api/v1/statuses/:id/reblog` | 必須 | ブーストする |
| `POST` | `/api/v1/statuses/:id/unreblog` | 必須 | ブーストを解除する |

`POST /api/v1/statuses` の本に関係する拡張フィールドは次とする。

```json
{
  "status": "読了しました。",
  "visibility": "public",
  "book_isbns": ["9784101001548", "9784101001555"],
  "primary_book_isbn": "9784101001548"
}
```

- `book_isbns` は任意で、ISBN-13を1冊以上指定する。指定がない投稿は通常投稿である。
- 指定したISBNはサーバーの書誌カタログに存在しなければならない。
- 複数冊を指定する場合、`primary_book_isbn` は必須で、`book_isbns` の要素でなければならない。
- 本に紐付く投稿はActivityPubで連合する際、書誌の構造化データを追加できる。通常投稿も同様に連合するが、書誌データは持たない。

### 絵文字リアクション

| Method | Path | 認証 | 用途 |
| --- | --- | --- | --- |
| `GET` | `/api/v1/statuses/:id/reactions` | 任意 | 投稿の絵文字リアクション集計を取得する |
| `POST` | `/api/v1/statuses/:id/reactions` | 必須 | 絵文字リアクションを付与する |
| `DELETE` | `/api/v1/statuses/:id/reactions/:emoji` | 必須 | 絵文字リアクションを解除する |

作成時の本文は `{ "emoji": "📖" }`、またはカスタム絵文字なら
`{ "emoji": ":yomiba_reading:" }` とする。同一ユーザーによる同一投稿・同一絵文字は
冪等に扱う。

リアクションがサーバーの `reaction_state_rules` に登録され、かつ投稿に主となる本がある場合、
リアクションした本人の `user_books` の状態も更新する。複数冊投稿でも状態更新の対象は
`primary_book_isbn` の1冊だけである。

## タイムライン

### Mastodon互換の基本タイムライン

既存クライアントのため、以下はGETで提供する。

| Path | 意味 |
| --- | --- |
| `GET /api/v1/timelines/home` | ログイン中のユーザーのホームタイムライン |
| `GET /api/v1/timelines/public?local=true` | ローカルアカウントの公開投稿 |
| `GET /api/v1/timelines/public?local=false` | ローカルで観測できる公開投稿 |

### Yomiba複合タイムライン

複数の条件を本文（JSON body）で指定するため、`POST /api/v1/timelines/query` を提供する。
読み取りAPIだが、GETのbodyはプロキシやクライアントで失われることがあるためPOSTにする。

```json
{
  "base": "public",
  "origins": ["local", "federated"],
  "book": {
    "attached": "only",
    "isbns": ["9784101001548"],
    "registration_states": ["reading", "read"],
    "match": "any"
  },
  "limit": 20,
  "max_id": "01J..."
}
```

| フィールド | 値 | 意味 |
| --- | --- | --- |
| `base` | `public` / `home` | 検索対象。`home` は認証必須で、自分とフォロー中アカウントの投稿に限定する |
| `origins` | `local` / `federated` の配列 | 投稿者の所属で絞る。両方指定時は和集合、未指定時は両方 |
| `book.attached` | `any` / `only` / `exclude` | 本の紐付けを問わない／ある投稿だけ／ない投稿だけ |
| `book.isbns` | ISBN-13の配列 | 指定した本のいずれかを紐付けた投稿に絞る |
| `book.registration_states` | 読書状態の配列 | ログイン中ユーザーの棚における本の状態で絞る。認証必須 |
| `book.match` | `any` / `all` | ISBNまたは登録状態を複数指定した場合の一致条件。既定は `any` |

すべての指定カテゴリはANDで組み合わせる。`origins` の配列内だけはORである。
たとえば「ホーム内の、連合先ユーザーによる、読書中または読了の本が紐付く投稿」は次になる。

```json
{
  "base": "home",
  "origins": ["federated"],
  "book": {
    "attached": "only",
    "registration_states": ["reading", "read"],
    "match": "any"
  }
}
```

投稿に複数冊が紐付く場合、ISBN・登録状態の判定は紐付いた本のいずれかが一致すれば含める。
`book.match: "all"` の場合だけ、指定したすべてのISBNまたは状態条件を満たす必要がある。

## 本と読書棚

### 公開書誌・本の詳細

| Method | Path | 認証 | 用途 |
| --- | --- | --- | --- |
| `GET` | `/api/v1/books/search?q=:query` | 任意 | ISBN、題名、著者で本を検索する |
| `GET` | `/api/v1/books/isbn/:isbn13` | 任意 | ISBN-13を正規キーとして本の版を取得する |
| `GET` | `/api/v1/books/isbn/:isbn13/statuses` | 任意 | 当該ISBNに紐付く、閲覧者に公開可能な投稿を取得する |
| `POST` | `/api/v1/books` | 必須 | 書誌カタログへ本の候補を登録する |

`POST /api/v1/books` は、ISBN、題名、出版社、刊行日、著者・翻訳者を受け取る。
既存ISBNとの重複時は `409 Conflict` を返す。書誌の編集・統合・削除は管理者APIのみで行う。

### 自分の棚と状態

| Method | Path | 認証 | 用途 |
| --- | --- | --- | --- |
| `GET` | `/api/v1/me/books` | 必須 | 自分の棚を状態・ISBNなどで絞って取得する |
| `GET` | `/api/v1/me/books/isbn/:isbn13` | 必須 | 自分の当該本の状態を取得する |
| `PUT` | `/api/v1/me/books/isbn/:isbn13` | 必須 | 読書状態、開始日、終了日、評価、公開範囲を更新する |
| `DELETE` | `/api/v1/me/books/isbn/:isbn13` | 必須 | 棚から本を外す |
| `GET` | `/api/v1/me/books/events` | 必須 | 読書状態の変更履歴を取得する |

状態更新の本文例:

```json
{
  "state": "reading",
  "started_on": "2026-09-27",
  "visibility": "followers"
}
```

このAPIはローカルの `user_books` を操作するものであり、状態単体をActivityPubで連合しない。

## 検索

| Method | Path | 認証 | 用途 |
| --- | --- | --- | --- |
| `GET` | `/api/v2/search?q=:query&type=accounts,statuses,books` | 任意 | アカウント、投稿、本を横断検索する |
| `GET` | `/api/v1/books/search?q=:query` | 任意 | 本だけを検索する |

検索の実体はMeilisearchを使うが、検索結果の権限確認は必ずアプリケーションとPostgreSQL側で行う。
非公開投稿や閲覧権限のない棚情報を検索インデックスから返してはならない。

## 管理者API

すべて管理者権限が必要で、`/api/v1/admin` 以下に置く。

| Method | Path | 用途 |
| --- | --- | --- |
| `GET` | `/api/v1/admin/books` | 書誌の検索・重複候補を確認する |
| `POST` | `/api/v1/admin/books` | 書誌を登録する |
| `PATCH` | `/api/v1/admin/books/isbn/:isbn13` | 書誌を修正する |
| `POST` | `/api/v1/admin/books/merge` | 重複した版・作品を統合する |
| `GET` | `/api/v1/admin/reaction-state-rules` | 絵文字と状態の対応を取得する |
| `PUT` | `/api/v1/admin/reaction-state-rules` | 絵文字と状態の対応を一括更新する |
| `GET` | `/api/v1/admin/federation/instances` | 連合先の状態・配送失敗を確認する |
| `POST` | `/api/v1/admin/federation/instances/:domain/suspend` | 指定サーバーとの連合を停止する |

## ActivityPub公開エンドポイント

これらはMastodon APIとは別で、通常はBearer Tokenを要求しない。HTTP Signatureなどの
ActivityPubの検証を行う。

| Method | Path | 用途 |
| --- | --- | --- |
| `GET` | `/.well-known/webfinger?resource=acct:...` | Actorの発見 |
| `GET` | `/users/:username` | Actorを返す |
| `GET` | `/users/:username/outbox` | 公開Outboxを返す |
| `POST` | `/users/:username/inbox` | 個人Inboxを受信する |
| `POST` | `/inbox` | Shared Inboxを受信する |

Inboxは速やかに `202 Accepted` を返し、署名検証・JSONの解析・DB更新はワーカーで行う。

## Streaming API

Mastodon互換のStreaming APIをWebSocketで提供する。

| Path | 認証 | 対象 |
| --- | --- | --- |
| `/api/v1/streaming?stream=user` | 必須 | ホーム、通知、更新イベント |
| `/api/v1/streaming?stream=public` | 任意 | 公開タイムライン |
| `/api/v1/streaming?stream=hashtag&tag=:tag` | 任意 | 指定タグ |

複合タイムラインは初期リリースではHTTPの `POST /timelines/query` のみとする。
利用状況を見て、同じフィルタJSONを購読開始時に送る `stream=query` を追加する。
