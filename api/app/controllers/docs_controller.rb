# frozen_string_literal: true

# API 仕様の公開。
#
#   GET /openapi.json — OpenAPI 3.1 ドキュメント
#   GET /docs         — Swagger UI
#
# 仕様は公開情報だが、管理 API の実行には X-Admin-Key が必要。
# 仕様書に秘密情報を含めないことは OpenapiDocument 側で担保する。
class DocsController < ApplicationController
  SWAGGER_UI_VERSION = "5.17.14"

  def openapi
    render json: OpenapiDocument.as_json
  end

  def index
    render html: swagger_ui_html.html_safe, content_type: "text/html" # rubocop:disable Rails/OutputSafety
  end

  private

  def swagger_ui_html
    <<~HTML
      <!doctype html>
      <html lang="ja">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
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
