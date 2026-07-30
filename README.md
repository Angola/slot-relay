# <プロジェクト名>

<一言でこのプロダクトは何か>

> このリポジトリは [`chagura-boilerplate`](https://github.com/Angola/chagura-boilerplate)
> テンプレートから作成されています。**まずこの README を自分のプロジェクト用に書き換えてください。**
> テンプレート自体の使い方・設計思想は `docs/TEMPLATE_GUIDE.md` を参照（セットアップ後は削除可）。

## セットアップ（テンプレートから作成した直後にやること）

> **「Use this template」で作成した場合、`Template Init` ワークフローが初回に自動で**
> この README をリポジトリ名だけの最小構成に書き換え・`VERSION` を `0.1.0` にリセット・
> プレースホルダ（`<プロジェクト名>` / `<owner>/<repo>`）を置換・`docs/TEMPLATE_GUIDE.md` を削除
> します（下記 1・4〜6・8 は自動処理済み）。**手動コピー（`cp`）で使った場合は自動処理が走らない**
> ので、以下を手で行ってください。

1. **プレースホルダを置換**（`<...>` を全文検索して置換）：

   | プレースホルダ | 意味 |
   | --- | --- |
   | `<プロジェクト名>` | プロダクト名／コードネーム |
   | `<owner>/<repo>` | GitHub のオーナー／リポジトリ名 |
   | `<一言でこのプロダクトは何か>` | この README の 1 行説明 |

2. **リポジトリ設定**：`Settings > General > Pull Requests` で **Squash merging のみ** を許可する
   （バージョン自動採番 `version-bump.yml` がスカッシュコミットのメッセージ＝PR タイトルを前提にしているため）。
3. `CLAUDE.md` の「リポジトリ構成」を実際の構成に合わせて書き換える。
4. `docs/MILESTONE.md` に「まずどこまで（1.0 など）で何をしたいか」をざっくり書く。
5. `docs/DESIGN.md` に §1 から実際のプロダクト定義を書く。
6. `VERSION` は `0.1.0` のまま開始（以降は GitHub Actions が自動更新するので手で触らない）。
7. `.github/workflows/template-init.yml` と `.github/.template-init-pending` が残っていれば削除する。
8. 不要になった `docs/TEMPLATE_GUIDE.md` を削除する。

## 開発ルール

このリポジトリの開発ルール（ブランチ運用・バージョニング・ドキュメント・完了チェックリスト）は
**`CLAUDE.md`** に集約されている。作業前に必ず読むこと。

- **やりたいこと** → `docs/MILESTONE.md`（ざっくりした目標・区切りは自由）
- **経緯・決定（なぜ）** → `docs/plans/`（作業ごとの plan を 1 ファイルで残す）
- **変更史（何を）** → `docs/CHANGELOG.md`（Keep a Changelog）
- **設計** → `docs/DESIGN.md` ／ **セキュリティ** → `docs/SECURITY.md`

## プロジェクト概要

<!-- ここから下を、このプロダクトの説明に書き換える。以下は雛形。 -->

### 何を作るか

<プロダクトの目的・解く課題・対象ユーザー>

### 技術スタック

<選定した技術。`docs/DESIGN.md` §2 にも反映する>

### セットアップ / 開発

```bash
# 例: 依存インストール・起動手順など、技術選定後に記載する
```

### デプロイ

デプロイ手順は `docs/DEPLOY.md` を参照。
