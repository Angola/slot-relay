# frozen_string_literal: true

require "test_helper"

# 運用エンドポイントと API 仕様の公開。
class OpsControllerTest < ActionDispatch::IntegrationTest
  test "/health は 200 とバージョンを返す" do
    get "/health"

    assert_response :success
    assert_equal "ok", response.parsed_body["status"]
    assert_predicate response.parsed_body["version"], :present?
  end

  test "/ready は DB 接続を確認する" do
    get "/ready"

    assert_response :success
    assert_equal "ready", response.parsed_body["status"]
    assert_equal "ok", response.parsed_body["database"]
  end

  test "/openapi.json は OpenAPI 3.1 ドキュメントを返す" do
    get "/openapi.json"

    assert_response :success
    body = response.parsed_body

    assert_equal "3.1.0", body["openapi"]
    assert_equal "slot-relay 予約 API", body.dig("info", "title")
    assert_includes body["paths"].keys, "/v1/public/booking-types/{slug}/availability"
    assert_includes body["paths"].keys, "/v1/admin/booking-types"
    assert_equal "X-Admin-Key", body.dig("components", "securitySchemes", "adminKey", "name")
  end

  test "OpenAPI ドキュメントに秘密情報を含めない" do
    get "/openapi.json"

    assert_response :success
    [
      SlotRelayTestConfig::ADMIN_API_KEY,
      "BEGIN PRIVATE KEY",
      "SMTP_PASSWORD",
      "slot-relay@example.iam.gserviceaccount.com"
    ].each do |secret|
      assert_not_includes response.body, secret
    end
  end

  test "OpenAPI に定義されたすべての $ref がスキーマとして存在する" do
    get "/openapi.json"

    document = response.parsed_body
    defined_schemas = document.dig("components", "schemas").keys
    referenced = collect_refs(document).map { |ref| ref.delete_prefix("#/components/schemas/") }.uniq

    assert_empty referenced - defined_schemas
  end

  test "/docs は Swagger UI を返す" do
    get "/docs"

    assert_response :success
    assert_match %r{text/html}, response.media_type
    assert_includes response.body, "swagger-ui"
    assert_includes response.body, "/openapi.json"
  end

  test "/docs は検索エンジンに拾わせない" do
    get "/docs"

    assert_includes response.body, %(name="robots" content="noindex, nofollow")
  end

  # 本番では既定で閉じる。管理 API のパス構成を偵察させないため（docs/SECURITY.md）。
  # 403 ではなく 404 にして「ここに何かある」ことも伝えない。
  test "ドキュメントが無効なら /docs は 404" do
    configure_slot_relay!(api_docs_enabled: false)

    get "/docs"

    assert_response :not_found
    assert_not_includes response.body, "swagger-ui"
  end

  test "ドキュメントが無効なら /openapi.json も 404" do
    configure_slot_relay!(api_docs_enabled: false)

    get "/openapi.json"

    assert_response :not_found
    assert_not_includes response.body, "/v1/admin"
  end

  test "ドキュメントが無効でも /health と /ready は開いている（ヘルスチェック用）" do
    configure_slot_relay!(api_docs_enabled: false)

    get "/health"
    assert_response :success

    get "/ready"
    assert_response :success
  end

  private

  def collect_refs(node)
    case node
    when Hash
      node.flat_map { |key, value| key == "$ref" ? [value] : collect_refs(value) }
    when Array
      node.flat_map { |value| collect_refs(value) }
    else
      []
    end
  end
end
