# ローカル開発環境を compose に載せる

- 日付: 2026-07-30
- ブランチ: `feat/google-oauth-calendar-selection`（Google OAuth 移行と同じ PR に含める）

## やりたいこと

`docker compose up -d` だけでローカルの開発環境（API + PostgreSQL + 参照実装 UI）が
立ち上がる状態にする。手順をファイルとしてリポジトリに残し、環境ごとの差分を `.env` に逃がす。

## 背景・なぜ

README の「ローカルで動かす」は **ホストに Ruby 3.3 / PostgreSQL 16 が入っている前提**だった。
実際に環境を作ろうとしたところ、次の理由でその前提が成立しなかった。

- ホストに Ruby が無く、apt の候補は 1:3.0（必要なのは 3.3.6）。rbenv / mise 等も未導入
- ホストの PostgreSQL は 17 で、しかも停止中（要求は 16。`btree_gist` の排他制約に依存するため
  メジャーバージョンを合わせたい）
- ポート 3000 / 3001 は同一ホストの別プロジェクト（metabase / kencos-api）が使用中

ad-hoc な `docker run` を並べれば動くが、コマンドが長く再現性がない。ファイルに落とす。

## 方針

### 追加したファイル

| ファイル | 役割 |
| --- | --- |
| `compose.yaml`（リポジトリ最上位） | db / api / web の 3 サービス |
| `api/Dockerfile.dev` | ローカル用イメージ。本番用 `api/Dockerfile` とは別物 |
| `.env.example`（リポジトリ最上位） | compose のポート・uid の既定値 |

`compose.yaml` を最上位に置くのは、ビルドコンテキストが `./api` と `./web` の
両方にまたがるため。`CLAUDE.md` の「リポジトリ構成」もあわせて更新した。

### 決めたこと

- **本番用 Dockerfile を流用せず、開発用を別に作る。** 本番用は `RAILS_ENV=production` /
  `BUNDLE_WITHOUT=development` / `config.force_ssl = true` で、HTTP の curl が
  リダイレクトされるなどローカル検証に向かない。ソースを焼き込む点も開発と噛み合わない。
- **gem は `api/vendor/bundle` に置く**（`.gitignore` 済み）。名前付きボリュームでも良いが、
  ホストから中身を読めるほうがデバッグが早く、イメージ再ビルドでも消えない。
- **コンテナはホストと同じ uid/gid で動かす。** バインドマウント先に root 所有の
  ファイル（`log/`・`tmp/`）を作らせないため。1000 以外の環境は `.env` で上書きする。
- **ポートは既定を 3011 / 3012 / 55432 にずらす。** 3000 / 3001 は衝突実績があるため。
  空いている環境では `.env` で本来の 3000 / 3001 に戻してよい。
- **DB のポートをホストへ公開する（55432）。** GUI クライアントや `psql` から
  直接覗けるほうが開発中の確認が速い。ローカル専用なので認証は postgres/postgres のまま。
- **DB データは名前付きボリューム `db-data`。** 匿名ボリュームだと `docker rm` で
  実質失われ、どれが自分のデータか分からなくなる。`docker compose down -v` で明示的に消す。
- **`bundler` はイメージ内で 4.0.9 を入れる。** `Gemfile.lock` の `BUNDLED WITH` が 4.0.9 で、
  チェックサム付き lock は ruby イメージ同梱の bundler 2.x では読めない。
- **`VERSION` を個別にマウントする。** `SlotRelay::VERSION` が `Rails.root.join("../VERSION")` を
  見るが、api サービスのマウントは `./api` だけなので `/VERSION` が無いと `unknown` になる。

### seeds への変更

参照実装 UI のオリジンが `http://localhost:3000` 固定だと、ポートをずらした瞬間に
CORS で弾かれる。`DEV_ALLOWED_ORIGINS`（compose が渡す）で追加できるようにした。
既定値は従来どおり `http://localhost:3000` なので、ホスト直実行の手順は壊れない。

## 経緯・メモ

- 動作確認は compose 上で実施。API テスト 176 件・web テスト 15 件が通り、
  ヘッドレス Chrome で「日付選択 → 時間選択 → 入力 → 予約確定 → キャンセル」まで到達した。
- 確認メールは development では `api/tmp/mails/` にファイル出力される（SMTP へは送らない）。
- Google 未連携でも `NullClient` が使われるため、compose だけで一通り触れる。

## 積み残し

- `web` サービスは起動のたびに `npm install` を実行する。node_modules はバインドマウント上に
  残るので 2 回目以降は速いが、CI 的な再現性を求めるなら `npm ci` + 専用ボリュームに変える余地がある。
