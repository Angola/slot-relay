# frozen_string_literal: true

# 予約メニューごとの許可 Origin。スキーム + ホスト + 任意ポートのみを保持し、
# パス・クエリを含む文字列は受け付けない（Origin ヘッダと厳密一致で比較するため）。
class BookingTypeOrigin < ApplicationRecord
  belongs_to :booking_type, inverse_of: :origins

  validates :origin,
            presence: true,
            length: { maximum: 255 },
            uniqueness: { scope: :booking_type_id }
  validate :origin_must_be_scheme_and_host_only

  private

  def origin_must_be_scheme_and_host_only
    return if origin.blank?

    uri = URI.parse(origin)
    raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    raise URI::InvalidURIError if uri.host.blank?
    raise URI::InvalidURIError if uri.path.present? || uri.query.present? || uri.fragment.present?
    raise URI::InvalidURIError if uri.userinfo.present?
  rescue URI::InvalidURIError
    errors.add(:origin, "は http(s)://host[:port] 形式である必要があります")
  end
end
