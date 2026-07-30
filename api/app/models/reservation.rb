# frozen_string_literal: true

# 予約。
#
# status の遷移:
#   pending  --(Google 予定作成成功)--> confirmed --(キャンセル)--> cancelled
#      |
#      +-----(Google 予定作成失敗)----> failed
#
# pending は「同時リクエストを直列化するための仮確保」であり、expires_at を過ぎたものは
# 無効として扱う（DB の排他制約は expires_at を見られないため、期限切れ pending は
# 予約作成時に明示的に掃除する）。
class Reservation < ApplicationRecord
  STATUSES = %w[pending confirmed cancelled failed].freeze
  BLOCKING_STATUSES = %w[pending confirmed].freeze

  # 仮確保の寿命。Google API 呼び出し + 予定作成の所要時間に対して十分な長さ。
  PENDING_TTL = 5.minutes

  MAX_ANSWER_KEYS = 30
  MAX_ANSWER_VALUE_LENGTH = 2_000

  belongs_to :booking_type, inverse_of: :reservations

  # 生のキャンセルトークンは発行時のみメモリ上に持つ（DB にはハッシュのみ保存）。
  attr_accessor :cancel_token

  validates :public_id, presence: true, uniqueness: true
  validates :start_at, :end_at, presence: true
  validates :guest_name, presence: true, length: { maximum: 120 }
  validates :guest_email, presence: true, length: { maximum: 255 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :guest_company, length: { maximum: 120 }, allow_nil: true
  validates :guest_phone, length: { maximum: 40 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_at_after_start_at
  validate :answers_within_limits

  scope :confirmed, -> { where(status: "confirmed") }
  scope :cancelled, -> { where(status: "cancelled") }

  # 枠を塞いでいる予約。confirmed は常に、pending は期限内のものだけ。
  scope :blocking, ->(now = Time.current) {
    where(status: "confirmed").or(where(status: "pending").where(expires_at: now..))
  }

  scope :expired_pending, ->(now = Time.current) {
    where(status: "pending").where(expires_at: ...now)
  }

  scope :overlapping, ->(start_at, end_at) {
    where("start_at < ? AND end_at > ?", end_at, start_at)
  }

  before_validation :assign_public_id, on: :create

  class << self
    def generate_public_id
      "res_#{SecureRandom.urlsafe_base64(18).tr("-_", "ab")}"
    end

    def generate_cancel_token
      SecureRandom.urlsafe_base64(32)
    end

    def hash_cancel_token(token)
      return nil if token.blank?

      OpenSSL::Digest::SHA256.hexdigest(token)
    end

    # 生トークンから予約を引く。トークンを知っている人だけが参照・キャンセルできる。
    def find_by_cancel_token(token)
      digest = hash_cancel_token(token)
      return nil if digest.blank?

      find_by(cancel_token_hash: digest)
    end
  end

  # 新しいキャンセルトークンを発行し、ハッシュだけを属性に設定する。
  def issue_cancel_token!
    self.cancel_token = self.class.generate_cancel_token
    self.cancel_token_hash = self.class.hash_cancel_token(cancel_token)
    cancel_token
  end

  def pending? = status == "pending"
  def confirmed? = status == "confirmed"
  def cancelled? = status == "cancelled"
  def failed? = status == "failed"

  def cancellable?
    confirmed?
  end

  private

  def assign_public_id
    self.public_id ||= self.class.generate_public_id
  end

  def end_at_after_start_at
    return if start_at.blank? || end_at.blank?
    return if start_at < end_at

    errors.add(:end_at, "は start_at より後である必要があります")
  end

  # answers は予約メニューごとに項目が変わるためスキーマを固定しない。
  # 代わりにキー数・値の長さだけを制限して、無制限の JSON 流入を防ぐ。
  def answers_within_limits
    return if answers.blank?

    unless answers.is_a?(Hash)
      errors.add(:answers, "はオブジェクトである必要があります")
      return
    end

    errors.add(:answers, "の項目数が多すぎます（最大 #{MAX_ANSWER_KEYS}）") if answers.size > MAX_ANSWER_KEYS

    answers.each do |key, value|
      errors.add(:answers, "の値は文字列である必要があります（#{key}）") unless value.is_a?(String)
      next unless value.is_a?(String) && value.length > MAX_ANSWER_VALUE_LENGTH

      errors.add(:answers, "の値が長すぎます（#{key} / 最大 #{MAX_ANSWER_VALUE_LENGTH} 文字）")
    end
  end
end
