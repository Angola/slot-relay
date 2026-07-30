# PROJECT_STATUS.json / DECISIONS.json 廃止と MILESTONE.md・plans/ 導入

- date: 2026-07-13

## やりたいこと

固定スキーマの JSON による記録管理（`PROJECT_STATUS.json`＝現在地、`DECISIONS.json`＝決定史）を
まるごと廃止し、記録を人が読む Markdown に一本化する。あわせて `docs/MILESTONE.md` を新設して
「ざっくりやりたいこと」を書けるようにする。

## 背景・なぜ

- 作業のたびに固定スキーマ JSON を更新し、`schema-check.yml` が CI で検証する運用は
  メンテ負荷が高く、**開発が非常に遅くなる**（ユーザー指摘）。
- 「なぜそうしたか」は追記専用 JSON ではなく、**作業の起点となる plan にそのまま経緯ごと残す**方が自然。
- 「どこまでに何をしたいか」は、区切り自由・気軽に書ける `MILESTONE.md` があるとよい。

## 方針

- 削除: `PROJECT_STATUS.json` / `PROJECT_STATUS.schema.json` / `DECISIONS.json` /
  `DECISIONS.schema.json` / `.github/workflows/schema-check.yml` / `.claude/skills/project-status/`。
- 新設: `docs/MILESTONE.md`（緩いスケルトン）、`docs/plans/`（本ファイルの置き場・README で運用説明）。
- 記録は 3 分離を維持しつつ Markdown 化: やりたいこと→`MILESTONE.md` / 経緯・決定→`plans/` /
  変更史→`CHANGELOG.md`。
- 参照更新: `CLAUDE.md` / `README.md` / `docs/TEMPLATE_GUIDE.md` / `docs/DESIGN.md` /
  `docs/CODE_READING.md` / `.github/pull_request_template.md`。
- `version-bump.yml` / `template-init.yml` は JSON を参照しないため変更なし。

## 経緯・メモ

- ユーザー確認済みの決定: 経緯の置き場所は `docs/plans/` を新設 / `MILESTONE.md` は CLAUDE.md の
  「維持すべき docs」必須リストに入れる。
- 本ファイル自体が、新しい「plan を経緯ごと docs に残す」運用の最初の実例（ドッグフーディング）。
