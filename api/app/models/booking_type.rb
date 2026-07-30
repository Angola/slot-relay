# frozen_string_literal: true

# 予約メニュー。1 つのサイト・1 つの相談枠に対応する設定のかたまり。
# 公開 API は slug で、管理 API は id で参照する。
class BookingType < ApplicationRecord
  STATUSES = %w[active inactive].freeze

  has_many :origins,
           class_name: "BookingTypeOrigin",
           dependent: :destroy,
           inverse_of: :booking_type
  has_many :weekly_availabilities, dependent: :destroy, inverse_of: :booking_type
  has_many :availability_overrides, dependent: :destroy, inverse_of: :booking_type
  has_many :reservations, dependent: :restrict_with_error, inverse_of: :booking_type

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug,
            presence: true,
            uniqueness: true,
            length: { maximum: 80 },
            format: {
              with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
              message: "は英小文字・数字・ハイフンのみ使用できます"
            }
  validates :description, length: { maximum: 2_000 }, allow_nil: true
  validates :duration_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 8 * 60 }
  validates :minimum_notice_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 * 24 * 60 }
  validates :booking_window_days,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }
  validates :buffer_before_minutes, :buffer_after_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 24 * 60 }
  validates :status, inclusion: { in: STATUSES }
  validate :time_zone_must_be_known

  scope :active, -> { where(status: "active") }

  def active?
    status == "active"
  end

  # ActiveSupport::TimeZone。枠の生成はこのゾーンの壁時計時刻で行う。
  def tz
    ActiveSupport::TimeZone[time_zone]
  end

  def allowed_origins
    origins.map(&:origin)
  end

  # 予定の登録先カレンダー。メニュー単位の指定がなければ環境変数の既定値を使う。
  def booking_calendar_id
    google_booking_calendar_id.presence || SlotRelay.config.google_booking_calendar_id
  end

  # 空き判定に使うカレンダー。設定画面で選んでいなければ環境変数の既定値を使う
  # （GOOGLE_BUSY_CALENDAR_IDS からの移行期の互換）。
  def busy_calendar_ids
    ids = Array(google_busy_calendar_ids).compact_blank
    ids.presence || SlotRelay.config.google_busy_calendar_ids
  end

  private

  def time_zone_must_be_known
    return if time_zone.blank?
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "は有効な IANA タイムゾーン名である必要があります")
  end
end
