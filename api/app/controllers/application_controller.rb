# frozen_string_literal: true

class ApplicationController < ActionController::API
  # サービスクラスのエラーコード → HTTP ステータス。
  # 数値で書いているのは Rack のシンボル名（unprocessable_entity / unprocessable_content）が
  # バージョンによって揺れるため。
  ERROR_STATUSES = {
    bad_request: 400,
    invalid_range: 400,
    unauthorized: 401,
    forbidden_origin: 403,
    turnstile_failed: 403,
    not_found: 404,
    slot_unavailable: 409,
    request_in_progress: 409,
    not_cancellable: 409,
    not_reschedulable: 409,
    validation_failed: 422,
    invalid_start_at: 422,
    rate_limited: 429,
    calendar_error: 502,
    configuration_error: 503
  }.freeze

  DEFAULT_ERROR_STATUS = 500

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from AvailabilityCalculator::RangeTooWide, with: :render_range_too_wide
  rescue_from SlotRelay::ConfigurationError, with: :render_configuration_error

  private

  # エラー応答の形式は全エンドポイントで共通（docs/DESIGN.md §3.6）。
  #   { "code": "SLOT_UNAVAILABLE", "message": "...", "details": [...] }
  def render_error(code, message, details: nil, status: nil)
    body = { code: code.to_s.upcase, message: message }
    body[:details] = details if details.present?

    render json: body, status: status || ERROR_STATUSES.fetch(code.to_sym, DEFAULT_ERROR_STATUS)
  end

  def render_service_failure(result)
    render_error(result.code, result.message, details: result.details)
  end

  def render_not_found(_exception = nil)
    render_error(:not_found, "リソースが見つかりません。")
  end

  def render_parameter_missing(exception)
    render_error(:bad_request, "必須パラメータが不足しています: #{exception.param}")
  end

  def render_range_too_wide(exception)
    render_error(:invalid_range, exception.message)
  end

  def render_configuration_error(exception)
    Rails.logger.error("[slot-relay] 設定エラー: #{exception.message}")
    render_error(:configuration_error, "サーバー設定が不足しているため処理できません。")
  end
end
