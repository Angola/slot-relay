# Changelog

このプロジェクトの特筆すべき変更はすべてこのファイルに記録する。

- フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に準拠
- バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う
- バージョン番号・タグ・GitHub Release は GitHub Actions
  （`.github/workflows/version-bump.yml`）が `main` へのスカッシュマージごとに自動採番する
- 作業のたびに `Unreleased` セクションへ変更内容を追記すること（CLAUDE.md 参照）

## [Unreleased]

### Added

- `.gitattributes` を新設し、`docs/CHANGELOG.md merge=union` を指定。複数 PR が `Unreleased` に
  追記した際のマージコンフリクトを、Git 組み込みの union マージドライバ（両方の行を残して自動マージ）
  で仕組みとして解消。あわせて `CLAUDE.md` にルールとして明記。

- `docs/MILESTONE.md` を新設。ざっくりした目標（「1.0 で何をしたいか」等）を区切り自由で書くファイル。
- `docs/plans/`（＋ `docs/plans/README.md`）を新設。作業ごとの plan（やりたいこと・背景・方針・経緯）を
  1 ファイルとして残す運用の受け皿。従来の `DECISIONS.json`（「なぜ」の記録）を置き換える。
- `Template Init` ワークフロー（`.github/workflows/template-init.yml`）を追加。テンプレートから
  作成した初回 push で README をリポジトリ名だけの最小構成に書き換え、`VERSION` を `0.1.0` に
  リセットし、プレースホルダを置換して初期化コミットを積む（実行後に自身と `docs/TEMPLATE_GUIDE.md`
  ・初期化マーカーを削除）。
- 未初期化マーカー `.github/.template-init-pending` を追加。

### Changed

- 記録の管理を Markdown 3 本（`docs/MILESTONE.md` / `docs/plans/` / `docs/CHANGELOG.md`）に一本化。
  それに伴い `CLAUDE.md` / `README.md` / `docs/TEMPLATE_GUIDE.md` / `docs/DESIGN.md` /
  `docs/CODE_READING.md` / `.github/pull_request_template.md` の記述を更新。
- `version-bump.yml` を、初期化マーカーが残っている間はバージョン bump しないようガード。
- テンプレートの VERSION ドリフト（テンプレ本体の bump 済みバージョンを引き継ぐ問題）とその
  リセット方針を `docs/TEMPLATE_GUIDE.md` / `README.md` に明記。

### Removed

- `PROJECT_STATUS.json` / `PROJECT_STATUS.schema.json` / `DECISIONS.json` / `DECISIONS.schema.json`
  を廃止（固定スキーマ JSON のメンテ負荷で開発が遅くなるため）。
- 上記 JSON を検証する `.github/workflows/schema-check.yml` を削除。
- `PROJECT_STATUS.json` / `DECISIONS.json` を読み取り報告する `.claude/skills/project-status/` を削除。

## [0.1.2] - 2026-07-11

### Added

- テンプレート利用ガイドを `docs/TEMPLATE_GUIDE.md` として分離（旧 README の内容）。

### Changed

- `README.md` を新規プロジェクト用のスケルトンに刷新（テンプレートから作成した repo が
  そのまま自分の README として使える形にし、セットアップ手順とプレースホルダ表を掲載）。

## [0.1.1] - 2026-07-11

### Added

- プロジェクトの初期セットアップ（boilerplate から生成）

### Changed

### Fixed
