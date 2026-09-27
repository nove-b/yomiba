# 今後の進め方

## 進め方の原則

ActivityPubは初めて実装するため、最初からMastodon互換や本の連合を目指さない。
各TODOは原則として半日以内に終わり、HTTPリクエスト・ユニットテスト・画面のいずれかで
完了を確認できる粒度にする。

ActivityPubでは、アカウントをActor、受信口をInbox、送信履歴をOutboxとして表す。
まずはこの三つとWebFingerを動かし、次に受信、最後に配送を実装する。
[W3C ActivityPub仕様](https://www.w3.org/TR/activitypub/)を一次資料とし、
Mastodon/Misskeyとの実際の相互運用は後半の検証環境で確認する。

各節は、前の節が完了するまで始めない。未完のTODOを増やさず、1つずつ完了にする。

## 0. 開発の土台

- [ ] Go moduleを作成し、`cmd/web` と `cmd/worker` が別コマンドで起動する最小構成を作る
- [ ] `Dockerfile` と `compose.yaml` を作り、Web・Worker・PostgreSQL・Redis・Meilisearchを起動する
- [ ] `GET /healthz` が常に200、`GET /readyz` が依存サービス接続時だけ200を返すようにする
- [ ] `.env.example` を作り、秘密情報を含めずにローカル起動できるようにする
- [ ] DBマイグレーション実行コマンドと、空DBからの起動確認を用意する
- [ ] 構造化ログにリクエストIDを出し、秘密情報・Authorizationヘッダーを出力しないことをテストする
- [ ] CIで `go test ./...`、静的解析、DBマイグレーション検証を実行する

完了条件: 新しい開発者がREADMEの手順だけでローカル起動し、`/readyz` を確認できる。

## 1. ローカルアカウントと通常投稿

- [ ] `instances`、`accounts`、`account_emails`、`email_login_tokens` のマイグレーションを作る
- [ ] メールアドレスとユーザー名による仮登録を実装する
- [ ] 使い捨てメール認証リンクを発行し、トークンはハッシュだけをDBに保存する
- [ ] 認証リンクを一度だけ消費してWebセッションを開始できるようにする
- [ ] `statuses` のマイグレーションと、通常投稿の作成・取得・削除を実装する
- [ ] 公開投稿だけを返すローカルタイムラインを実装する
- [ ] 投稿の公開範囲（`public` / `unlisted` / `followers` / `direct`）ごとの閲覧テストを書く

完了条件: ローカルユーザーがメール認証し、公開投稿を作成してタイムラインで読める。

## 2. ActivityPubの「読めるActor」を作る

この段階では他サーバーへ投稿を送らず、Yomibaのアカウントを外部から発見・取得できるようにする。

- [ ] Actor、Activity、Note、OrderedCollectionの最小JSONをfixtureとして書く
- [ ] `YOMIBA_BASE_URL` からActor・投稿・Activityの恒久URLを生成する関数を作る
- [ ] アカウントごとのActivityPub鍵ペアを生成・安全に保存する処理を作る
- [ ] `GET /.well-known/webfinger` を実装し、`acct:user@domain` からActor URLを返す
- [ ] `GET /users/:username` を実装し、`Person`、`id`、`inbox`、`outbox`、`publicKey` を返す
- [ ] `Accept: application/activity+json` とHTMLアクセスで適切なContent-Typeを返す
- [ ] `GET /users/:username/outbox` を空の `OrderedCollection` として返す
- [ ] curlと自動テストでWebFinger → Actor → Outboxの順に取得できることを確認する

完了条件: 公開URLを持つ検証環境で、Actor JSONと空のOutboxを手動確認できる。

## 3. Inboxを安全に受信する

この段階の目標は「受け取って記録する」だけであり、受信した内容をタイムラインへ表示しない。

- [ ] `federation_activities` のマイグレーションを作る
- [ ] `POST /inbox` と `POST /users/:username/inbox` を実装し、受信時は速やかに `202 Accepted` を返す
- [ ] リクエスト本文の最大サイズ、JSONの深さ、HTTPタイムアウトを設定する
- [ ] `activity_uri` の一意制約で、同じActivityを二重処理しないようにする
- [ ] 受信したJSONをキューへ入れ、Webリクエスト外のWorkerで処理する
- [ ] Actorの公開鍵を取得してHTTP Signatureを検証する
- [ ] URL取得時にlocalhost、プライベートIP、メタデータIPへのアクセスを拒否する（SSRF対策）
- [ ] 署名不正・期限切れ・未知のActivityを隔離記録し、成功時と同じ詳細エラーを送信元へ返さない

完了条件: 署名付きfixtureを受信・重複排除でき、無効な署名とSSRF先URLを拒否できる。

## 4. 最初の連合: 外部投稿を読む

- [ ] `Create` の中にある公開 `Note` だけを読み取る処理を実装する
- [ ] リモートActorを `accounts`、リモート投稿を `statuses` に正規化して保存する
- [ ] HTMLをサニタイズし、本文テキストを別に保存する
- [ ] リモート投稿の公開範囲を判定し、Public以外を公開タイムラインへ混ぜない
- [ ] 連合投稿を含む公開タイムラインを実装する
- [ ] リモートの `Delete` を受け、該当投稿を `deleted_at` にする
- [ ] `Create`、`Delete`、重複、未知Actorのfixtureテストを書く

完了条件: 検証用のリモートActorから届く公開Noteを、Yomibaの公開タイムラインで表示できる。

## 5. 最初の連合: 自分の投稿を送る

- [ ] `delivery_attempts` のマイグレーションを作る
- [ ] ローカルの公開投稿からActivityStreams `Note` と `Create` を組み立てる
- [ ] `GET /users/:username/outbox` で実際の公開投稿を `OrderedCollectionPage` として返す
- [ ] 配送先Actorから `inbox` / `sharedInbox` を取得する処理を作る
- [ ] 送信リクエストへHTTP Signatureを付与する
- [ ] Workerが配送し、成功・失敗・HTTPステータスを `delivery_attempts` に記録する
- [ ] 指数バックオフ、最大試行回数、手動再試行を実装する
- [ ] 自作の受信テストサーバーで、署名付きCreateが届くことを確認する
- [ ] 専用の検証アカウントを使い、Mastodonのテスト用インスタンスで1件の投稿を確認する

完了条件: Yomibaの公開投稿1件が、外部Mastodonのフォロワーに読める形で届く。

## 6. フォローとホームタイムライン

- [ ] `follows` のマイグレーションを作る
- [ ] 外部Actorへ `Follow` を配送する
- [ ] `Accept` を受信してフォロー状態を `accepted` に更新する
- [ ] 外部からの `Follow` を受信し、ローカルユーザーが承認できる画面とAPIを作る
- [ ] 承認時に `Accept` を配送する
- [ ] フォロー関係を使ってホームタイムラインを組み立てる
- [ ] Follow / Accept / Undoのfixtureテストを書く

完了条件: YomibaとMastodonのアカウントが相互にフォローでき、ホームで投稿を読める。

## 7. Mastodon互換APIの最小セット

- [ ] OAuthアプリ登録と認可コードによるトークン発行を実装する
- [ ] `verify_credentials`、アカウント取得、投稿作成・取得・削除を実装する
- [ ] `timelines/home` と `timelines/public` を実装する
- [ ] 代表的なMastodonクライアントでログイン・投稿・タイムライン表示を手動確認する
- [ ] 互換できない機能は `docs/07-api.md` に明記する

完了条件: 少なくとも1つの既存Mastodonクライアントで、ログイン・閲覧・投稿ができる。

## 8. Yomibaの読書機能（ローカル）

- [ ] `works`、`book_editions`、`book_identifiers`、`contributors` のマイグレーションを作る
- [ ] ISBN-10をISBN-13へ正規化し、重複登録を防ぐ処理を作る
- [ ] ISBN-13をキーとする本の登録・取得・検索APIを実装する
- [ ] `status_books` を実装し、1投稿へ複数冊を紐付けられるようにする
- [ ] 主となる1冊を必ず1冊選ぶUIとAPIバリデーションを作る
- [ ] `user_books` と `user_book_events` を実装する
- [ ] 本付き投稿だけを表示する複合タイムラインを実装する
- [ ] ISBN詳細ページで、その本に紐付く公開投稿を表示する

完了条件: ローカルで本を登録し、複数冊を付けて投稿し、ISBN詳細ページと読書専用タイムラインで確認できる。

## 9. リアクションと読書状態

- [ ] `reactions` と `reaction_state_rules` のマイグレーションを作る
- [ ] Unicode絵文字リアクションの作成・解除・集計を実装する
- [ ] 管理者が絵文字と読書状態の対応を設定できるようにする
- [ ] 状態変更時に `user_book_events` を必ず追記するトランザクションを実装する
- [ ] 複数冊投稿では主となる1冊だけが更新されるテストを書く
- [ ] 他人の投稿へ反応しても、投稿者の棚を変更しないテストを書く
- [ ] リアクションを外したときに状態を戻すかを仕様として決定し、実装・テストする

完了条件: 📖などの設定済み絵文字で、リアクションした本人の主となる本だけを状態変更できる。

## 10. 本付き投稿の連合と公開準備

- [ ] 本付き投稿のActivityPub拡張JSONをfixtureとして定義する
- [ ] 非対応サーバーでは本文だけが通常投稿として読めることを確認する
- [ ] 対応クライアントではISBN・タイトル・書影を表示する
- [ ] リモート投稿の未知の書誌拡張を安全に無視する
- [ ] Railway向けのWeb・Worker・DB・Redis・Meilisearchのテンプレートを作る
- [ ] EC2/GCE向けのCompose導入手順とバックアップスクリプトを検証する
- [ ] DB・ActivityPub秘密鍵・メディアの復元テストを行う
- [ ] 外部公開前に、連合・削除・再試行・メール認証の手動テストを実施する

完了条件: 第三者がDocker Composeで起動し、メール認証から外部Mastodonとのフォロー・投稿まで試せる。

## 今はやらないこと

- [ ] 非公開投稿・ダイレクトメッセージの外部配送
- [ ] Quote post、投票、リスト、ブックマーク、全文編集履歴
- [ ] Misskey固有のEmojiReact送受信
- [ ] 本の棚・読書状態そのもののActivityPub連合
- [ ] 複数Webレプリカ、Kubernetes、複数リージョン構成

これらは、公開投稿のCreate / DeleteとFollow / Acceptが安定し、相互運用テストを通過してから
別のTODOとして分解する。
