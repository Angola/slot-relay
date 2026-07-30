# frozen_string_literal: true

# サービスクラスの戻り値。成功時は value、失敗時は API のエラーコード・メッセージを持つ。
# コントローラはこの code をそのまま HTTP ステータスへ写す（ApplicationController::ERROR_STATUSES）。
class ServiceResult
  attr_reader :value, :code, :message, :details

  def self.success(value) = new(success: true, value: value)

  def self.failure(code, message, details: nil)
    new(success: false, code: code, message: message, details: details)
  end

  def initialize(success:, value: nil, code: nil, message: nil, details: nil)
    @success = success
    @value = value
    @code = code
    @message = message
    @details = details
  end

  def success? = @success
  def failure? = !@success
end
