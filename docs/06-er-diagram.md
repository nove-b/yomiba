# ER図

## ソーシャル・書誌・読書記録

```mermaid
erDiagram
    INSTANCES ||--o{ ACCOUNTS : hosts
    ACCOUNTS ||--o{ ACCOUNT_EMAILS : verifies
    ACCOUNT_EMAILS ||--o{ EMAIL_LOGIN_TOKENS : issues
    ACCOUNTS ||--o{ FOLLOWS : follows
    ACCOUNTS ||--o{ FOLLOWS : followed_by
    ACCOUNTS ||--o{ STATUSES : creates
    STATUSES ||--o{ STATUSES : replies_to
    STATUSES ||--o{ REACTIONS : receives
    ACCOUNTS ||--o{ REACTIONS : adds
    STATUSES ||--o{ STATUS_BOOKS : links
    BOOK_EDITIONS ||--o{ STATUS_BOOKS : attached_to
    WORKS ||--o{ BOOK_EDITIONS : has
    BOOK_EDITIONS ||--o{ BOOK_IDENTIFIERS : identified_by
    BOOK_EDITIONS ||--o{ BOOK_CONTRIBUTORS : credits
    CONTRIBUTORS ||--o{ BOOK_CONTRIBUTORS : contributes_to
    ACCOUNTS ||--o{ USER_BOOKS : owns
    BOOK_EDITIONS ||--o{ USER_BOOKS : tracked_as
    USER_BOOKS ||--o{ USER_BOOK_EVENTS : records
    STATUSES ||--o{ USER_BOOK_EVENTS : caused_by
    REACTIONS ||--o{ USER_BOOK_EVENTS : caused_by

    INSTANCES {
        uuid id PK
        text domain UK
        text actor_uri
        timestamptz blocked_at
        timestamptz suspended_at
    }

    ACCOUNTS {
        uuid id PK
        uuid instance_id FK
        text username
        text domain
        text uri UK
        text inbox_uri
        text public_key_pem
        boolean local
        timestamptz suspended_at
    }

    ACCOUNT_EMAILS {
        uuid id PK
        uuid account_id FK
        text email UK
        timestamptz verified_at
        boolean primary
    }

    EMAIL_LOGIN_TOKENS {
        uuid id PK
        uuid account_email_id FK
        text token_digest UK
        text purpose
        timestamptz expires_at
        timestamptz consumed_at
    }

    FOLLOWS {
        uuid id PK
        uuid follower_id FK
        uuid followee_id FK
        text state
        timestamptz accepted_at
    }

    STATUSES {
        uuid id PK
        text uri UK
        uuid account_id FK
        uuid in_reply_to_id FK
        uuid reblog_of_id FK
        text content_html
        text content_text
        text visibility
        timestamptz published_at
        timestamptz deleted_at
        boolean local
    }

    REACTIONS {
        uuid id PK
        uuid status_id FK
        uuid account_id FK
        text emoji
        text activity_uri UK
        boolean local
    }

    WORKS {
        uuid id PK
        text canonical_title
        text original_language
        text description
    }

    BOOK_EDITIONS {
        uuid id PK
        uuid work_id FK
        text title
        text publisher
        date published_on
        integer page_count
        text format
    }

    BOOK_IDENTIFIERS {
        uuid id PK
        uuid book_edition_id FK
        text scheme
        text value
    }

    CONTRIBUTORS {
        uuid id PK
        text name
        text sort_name
        text uri
    }

    BOOK_CONTRIBUTORS {
        uuid book_edition_id PK_FK
        uuid contributor_id PK_FK
        text role PK
    }

    STATUS_BOOKS {
        uuid status_id PK_FK
        uuid book_edition_id PK_FK
        boolean is_primary
        text source
    }

    USER_BOOKS {
        uuid account_id PK_FK
        uuid book_edition_id PK_FK
        text state
        date started_on
        date finished_on
        numeric rating
        text visibility
        timestamptz state_changed_at
    }

    USER_BOOK_EVENTS {
        uuid id PK
        uuid account_id FK
        uuid book_edition_id FK
        text from_state
        text to_state
        text source
        uuid status_id FK
        uuid reaction_id FK
        timestamptz created_at
    }
```

### 制約

- `accounts`: `(username, domain)` と `uri` は一意
- `account_emails`: `email` は一意。パスワードハッシュは保存しない
- `email_login_tokens`: トークン平文は保存せず、`token_digest` のみを保存する
- `follows`: `(follower_id, followee_id)` は一意
- `reactions`: `(status_id, account_id, emoji)` は一意
- `book_identifiers`: `(scheme, value)` は一意。ISBN-10はISBN-13へ正規化する
- `status_books`: 1投稿に複数冊を紐付けられる。ただし `is_primary = true` は投稿ごとに最大1件
- `user_books`: `(account_id, book_edition_id)` は一意。現在の読書状態を表す

`user_book_events` は状態変更の履歴であり、`user_books` の現在値を更新する際に必ず追加する。
絵文字リアクションによる変更では、`reaction_id` と `status_id` を保存する。

## 連合・配送

```mermaid
erDiagram
    INSTANCES ||--o{ ACCOUNTS : hosts
    FEDERATION_ACTIVITIES ||--o{ DELIVERY_ATTEMPTS : queues
    STATUSES o|--o{ FEDERATION_ACTIVITIES : represented_by
    ACCOUNTS o|--o{ FEDERATION_ACTIVITIES : acts_in

    FEDERATION_ACTIVITIES {
        uuid id PK
        text activity_uri UK
        text direction
        text activity_type
        text actor_uri
        text object_uri
        jsonb payload
        timestamptz received_at
    }

    DELIVERY_ATTEMPTS {
        uuid id PK
        uuid activity_id FK
        text inbox_uri
        text state
        integer attempt_count
        timestamptz next_attempt_at
        text last_error
        timestamptz delivered_at
    }
```

`federation_activities` はActivityPubの受信・送信JSONを監査・重複排除のために保存する。
通常の表示・検索はここを直接参照せず、正規化された `accounts`、`statuses`、`reactions` を使う。
`delivery_attempts` は送信を非同期化する永続キューである。

## 公開範囲

通常投稿と本に紐付いた投稿は `statuses` として連合する。本に紐付く投稿では、
`status_books` の主となる本の書誌情報をActivityPubの拡張データとして付与できる。

`user_books` と `user_book_events` は各サーバー内の読書棚・履歴であり、初期リリースでは
連合しない。リアクションした本人の状態だけを更新し、複数冊を紐付けた投稿では
`is_primary` の本だけがその対象となる。
