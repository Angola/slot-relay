<!--
PR タイトルは Conventional Commits 形式（feat: / fix: / docs: / chore: ...）。
スカッシュマージ後のコミットメッセージ（＝この PR タイトル）がバージョン自動更新の判定に使われる。
  BREAKING CHANGE / feat!: / [major] → major
  feat: / [minor]                    → minor
  それ以外                            → patch
-->

## 概要

<!-- この PR で何を・なぜ変えるか。関連する plan（docs/plans/）や milestone があれば書く -->

## 変更点

-

## 動作確認

<!-- どう検証したか（テスト・実機確認・スクショ等） -->

-

## チェックリスト（CLAUDE.md の作業完了チェックリスト）

- [ ] テストを書いた（ユニット / ユースケース / 画面遷移）
- [ ] 全テストを実行して通った
- [ ] セキュリティ上の懸念を `docs/SECURITY.md` に反映した
- [ ] 該当する docs（`DESIGN.md` / `CODE_READING.md` / `DEPLOY.md` ほか）を更新した
- [ ] `docs/CHANGELOG.md` の `Unreleased` に変更内容を追記した
- [ ] 作業の背景・方針・意思決定を `docs/plans/` に plan として残した
- [ ] 必要なら `docs/MILESTONE.md` を更新した
