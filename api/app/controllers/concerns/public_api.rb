# frozen_string_literal: true

# 公開 API 共通の振る舞い。CORS ヘッダの付与と許可 Origin の検証。
#
# CORS 自体はセキュリティ対策として数えない（HTTP クライアントは Origin を偽装できる）。
# ブラウザからの誤用を防ぐための最初の関門にすぎず、実質的な防御は
# Turnstile・レートリミット・入力検証・Idempotency-Key の併用で行う（docs/SECURITY.md）。
module PublicApi
  extend ActiveSupport::Concern

  ALLOWED_METHODS = "GET, POST, OPTIONS"
  ALLOWED_HEADERS = "Content-Type, Idempotency-Key"
  MAX_AGE = "600"

  included do
    before_action :apply_cors!
  end

  private

  # このリクエストで許可される Origin。予約メニュー単位で管理するため、
  # 各コントローラが対象の予約メニューを解決してから呼ばれる。
  def allowed_origins
    raise NotImplementedError
  end

  def apply_cors!
    append_vary_origin

    origin = request.headers["Origin"].presence
    # Origin ヘッダがないのはブラウザ以外（サーバー間呼び出し・curl）。
    # CORS は関係しないため許可し、Turnstile とレートリミットで守る。
    return if origin.nil?

    unless allowed_origins.include?(origin)
      render_error(:forbidden_origin, "このオリジンからのアクセスは許可されていません。")
      return
    end

    response.headers["Access-Control-Allow-Origin"] = origin
    response.headers["Access-Control-Allow-Methods"] = ALLOWED_METHODS
    response.headers["Access-Control-Allow-Headers"] = ALLOWED_HEADERS
    response.headers["Access-Control-Max-Age"] = MAX_AGE
  end

  # Origin によって応答が変わるため、キャッシュを分離させる。
  def append_vary_origin
    existing = response.headers["Vary"].to_s.split(",").map(&:strip)
    response.headers["Vary"] = (existing + ["Origin"]).uniq.join(", ")
  end
end
