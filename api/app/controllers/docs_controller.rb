# frozen_string_literal: true

# API 仕様の公開。
#
#   GET /openapi.json — OpenAPI 3.1 ドキュメント
#   GET /docs         — Swagger UI
#
# 仕様書に秘密情報を含めないことは OpenapiDocument 側で担保する。
#
# **本番では既定で閉じる（404）。** 秘密は入っていないが、管理 API のパス構成が
# そのまま見えると偵察が無料になり、誰でも開けるログインフォーム
# （/v1/admin/google/setup）がスキャナに拾われる。公開したいときだけ
# ENABLE_API_DOCS=true を設定する（docs/SECURITY.md）。
class DocsController < ApplicationController
  SWAGGER_UI_VERSION = "5.17.14"

  before_action :ensure_docs_enabled!

  def openapi
    render json: OpenapiDocument.as_json
  end

  def index
    render html: swagger_ui_html.html_safe, content_type: "text/html" # rubocop:disable Rails/OutputSafety
  end

  private

  # 403 ではなく 404 にする。403 だと「ここに何かある」ことを教えてしまう。
  def ensure_docs_enabled!
    render_not_found unless SlotRelay.config.api_docs_enabled
  end

  def swagger_ui_html
    <<~HTML
      <!doctype html>
      <html lang="ja">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <!-- 検索エンジンに拾わせない（管理 API のパスが載っているため） -->
          <meta name="robots" content="noindex, nofollow">
          <meta name="referrer" content="no-referrer">
          <title>slot-relay 予約 API リファレンス</title>
          <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@#{SWAGGER_UI_VERSION}/swagger-ui.css">
        </head>
        <body>
          <div id="swagger-ui"></div>
          <script src="https://unpkg.com/swagger-ui-dist@#{SWAGGER_UI_VERSION}/swagger-ui-bundle.js" crossorigin></script>
          <script>
            window.onload = () => {
              SwaggerUIBundle({ url: "/openapi.json", dom_id: "#swagger-ui", deepLinking: true });
            };
          </script>
        </body>
      </html>
    HTML
  end
end
