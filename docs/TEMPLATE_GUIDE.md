# chagura-boilerplate — テンプレート利用ガイド

> **このファイルはテンプレートの取扱説明です。** テンプレートから新しいリポジトリを作ったら、
> セットアップ完了後にこのファイル（`docs/TEMPLATE_GUIDE.md`）は**削除してよい**。
> プロジェクト本体の説明は、ルート直下の `README.md`（プロジェクト用スケルトン）に書く。

---

新規プロジェクトを立ち上げるときに **そのまま使える運用ルール一式**。
技術スタックには依存しない「プロジェクト運営の型」だけを集めてある（Tsumugi の運用から一般化）。

> **このリポジトリは GitHub の [Template repository](https://docs.github.com/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template) です。**
> 上部の **「Use this template」→「Create a new repository」** から新規リポジトリを作れば、
> 以下の同梱物がそのまま入った状態で開発を始められます。

## このテンプレの狙い（ポリシーの核）

1. **ルールのハブは 1 枚**（`CLAUDE.md`）。各ドメインの一次情報は専用ファイルへ委譲する。
2. **1 ドメイン = 1 ソース**：バージョン→`VERSION`、設計→`docs/DESIGN.md`、セキュリティ→`docs/SECURITY.md`。
3. **記録は役割で 3 分離**（すべて人が読む Markdown に一本化）:
   - **やりたいこと** → `docs/MILESTONE.md`（ざっくりした目標・区切りは自由）
   - **経緯・決定（なぜ）** → `docs/plans/`（作業ごとの plan を 1 ファイルで残す）
   - **変更史（何を）** → `docs/CHANGELOG.md`（Keep a Changelog・リリース単位）
4. **作業は plan 起点**：何かやるときは `docs/plans/` に plan を作り、背景・方針・経緯を残す。
5. **機械で強制できるものは機械に**：バージョン bump・タグ・Release・CHANGELOG 繰り上げは
   GitHub Actions が唯一の更新者。
6. **完了条件をチェックリスト化**：テスト・docs・セキュリティ・plan を「完了の定義」にする。

### なぜやりたいこと/経緯/変更史を分けるのか

同じ「記録」でも軸が違う。**やりたいこと**（milestone）はこれから何をするかのざっくりした目標。
**経緯・決定**（plan）はイベント単位で「なぜそうしたか」を残す記録。
**変更史**（changelog）はリリース単位で「何を」を人に見せる出力用の記録（GitHub Release にも出せる）。
粒度・更新周期・読者が違うので同じファイルにまとめない。以前は現在地/決定史を固定スキーマの
JSON で管理していたが、メンテ負荷で開発が遅くなるため廃止し、Markdown に一本化した。

## 使い方

### A. GitHub Template から作る（推奨）

1. このリポジトリの **「Use this template」→「Create a new repository」** をクリック。
2. 新しいリポジトリ名・オーナーを指定して作成する。
3. **リポジトリ設定でスカッシュマージのみを許可する**
   （Settings > General > Pull Requests → *Allow squash merging* だけを ON）。
   バージョン自動採番（`version-bump.yml`）がスカッシュコミットのメッセージ＝PR タイトルを前提にしているため。
4. 作成された最初の push で **`Template Init` ワークフローが自動初期化**する（下記）。
   完了後にリポジトリを clone し、残りの手順（リポジトリ設定・DESIGN の記述など）を行う。

#### 自動初期化（Template Init ワークフロー）

「Use this template」で作成したリポジトリでは、`.github/workflows/template-init.yml` が
**初回 push で 1 回だけ**走り、次を自動で行う：

- `README.md` を **リポジトリ名だけ**の最小構成（`# <repo>`）に書き換える
- `VERSION` を **`0.1.0` にリセット**する（テンプレ本体の bump 済みバージョンを引き継がせない）
- プレースホルダ `<プロジェクト名>` → リポジトリ名、`<owner>/<repo>` → 実オーナー/リポジトリ に置換
- `docs/TEMPLATE_GUIDE.md`（このファイル）・初期化ワークフロー・マーカーを削除
- 上記を `chore: initialize project from template [skip version]` の 1 コミットとして push

初期化が終わるまで（マーカー `.github/.template-init-pending` が残っている間）は
`version-bump.yml` もバージョンを bump しない。**手動コピー（方式 B）ではこの自動処理は走らない**
ので、README/VERSION/プレースホルダは手で整えること（下記）。

> **なぜ VERSION をリセットするのか**：テンプレート本体（この repo）は開発のたびに
> `version-bump.yml` が `VERSION` を上げていく（例：`0.1.2`）。テンプレートは全ファイルを
> そのままコピーするため、放置すると新プロジェクトがテンプレの途中バージョンから始まってしまう。
> 自動初期化（方式 A）はこれを `0.1.0` に戻す。方式 B では **手で `0.1.0` に戻すこと**。

### B. 手元でコピーして使う

```bash
# このリポジトリの中身を新規リポジトリ直下へコピー（隠しファイルも含める）
git clone https://github.com/<owner>/chagura-boilerplate.git
cp -r chagura-boilerplate/. /path/to/new-repo/
rm -rf /path/to/new-repo/.git   # テンプレの履歴は引き継がない
cd /path/to/new-repo && git init
```

### プレースホルダの置換

作成・コピー後、次のプレースホルダを埋める（`<...>` を全文検索して置換）：

| プレースホルダ | 意味 |
| --- | --- |
| `<プロジェクト名>` | プロダクト名／コードネーム |
| `<owner>/<repo>` | GitHub のオーナー／リポジトリ名 |
| `<一言でこのプロダクトは何か>` | README の 1 行説明 |

最低限やること：

1. `CLAUDE.md` の「リポジトリ構成」を実際の構成に合わせて書き換える（技術スタック依存の章）。
2. `docs/MILESTONE.md` に「まずどこまで（1.0 など）で何をしたいか」をざっくり書く。
3. `docs/DESIGN.md` に §1 から実際のプロダクト定義を書く。
4. `VERSION` を `0.1.0` に戻して開始する（テンプレ本体の bump 済みバージョンを消す。方式 A では自動）。
   以降は Actions が自動更新するので手で触らない。

## 同梱物

| パス | 役割 |
| --- | --- |
| `CLAUDE.md` | 開発ルールのハブ（AI エージェント／人間の両方が読む一次ルール） |
| `VERSION` | SemVer 1 行。Actions が唯一の更新者 |
| `docs/MILESTONE.md` | **やりたいこと**。ざっくりした目標（区切りは自由） |
| `docs/plans/` | **経緯・決定**。作業ごとの plan を 1 ファイルで残す |
| `docs/CHANGELOG.md` | **変更史**。Keep a Changelog 形式・`Unreleased` に随時追記 |
| `docs/SECURITY.md` | 「懸念｜対策方針｜状況」の 3 列表で管理（LLM リスク節つき） |
| `docs/DESIGN.md` | §番号見出しのプロダクト設計 |
| `docs/CODE_READING.md` | コードの読み方ガイド |
| `docs/DEPLOY.md` | デプロイ手順 |
| `.github/pull_request_template.md` | PR テンプレ（完了チェックリスト入り） |
| `.github/workflows/template-init.yml` | テンプレ作成直後の初回 push で自動初期化（README/VERSION/プレースホルダ）。実行後に自身を削除 |
| `.github/.template-init-pending` | 未初期化マーカー。初期化完了で削除される（version-bump もこれがある間は待つ） |
| `.github/workflows/version-bump.yml` | main への push ごとに自動 bump・タグ・Release |
| `.github/dependabot.yml` | `github-actions` の依存を weekly 更新 |
| `.gitignore` / `.editorconfig` | 汎用の最小規約 |

## スコープの前提（個人／少人数開発）

- 強制の重い仕組み（`CODEOWNERS`・必須レビュー・commit フック/husky/lefthook）は **入れていない**。
  規律は「ドキュメント＋PR チェックリスト」で担保する方針。
- 言語ごとの lint / test CI は **各プロジェクトの技術選定後に追加する**前提。
  同梱の CI は言語非依存にできる `version-bump` のみ。

### チーム化したら足す候補

- `.github/CODEOWNERS`（レビュー必須化）
- ブランチ保護ルール（PR 必須・CI green 必須・スカッシュマージ強制）
- commitlint / husky（Conventional Commits を機械強制）
- 言語別 CI（lint / test / 脆弱性スキャン）
