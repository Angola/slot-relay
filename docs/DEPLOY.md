# DEPLOY.md — デプロイ手順

> 各環境へのデプロイ方法・必要な環境変数・ロールバック手順をまとめる。

## 環境一覧

| 環境 | 用途 | URL | デプロイ方法 |
| --- | --- | --- | --- |
| local | 開発 | http://localhost:... | unknown |
| staging | 検証 | unknown | unknown |
| production | 本番 | unknown | unknown |

## 必要な環境変数

| 変数名 | 用途 | 例 / 既定 |
| --- | --- | --- |
| - | - | - |

## デプロイ手順

1. unknown

## ロールバック手順

1. unknown

## リリースフロー

- `main` へのスカッシュマージで `version-bump.yml` が自動でバージョン採番・タグ付け・GitHub Release 作成を行う。
- 各環境へのデプロイは <自動デプロイ / 手動> で行う。
