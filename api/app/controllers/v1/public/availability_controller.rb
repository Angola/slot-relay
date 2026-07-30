# frozen_string_literal: true

module V1
  module Public
    # GET /v1/public/booking-types/:slug/availability?from=2026-08-01&to=2026-08-07
    #
    # Google カレンダーに予定がある枠と、DB 上の有効な予約と重なる枠は返さない。
    # 枠が 0 件の日も `slots: []` で含める（カレンダー UI が休業日を描画できるようにするため）。
    class AvailabilityController < BaseController
      DEFAULT_RANGE_DAYS = 14

      def index
        from = parse_date(params[:from]) || default_from
        to = parse_date(params[:to]) || (from + DEFAULT_RANGE_DAYS - 1)

        return render_error(:invalid_range, "to は from 以降の日付を指定してください。") if to < from

        days = AvailabilityCalculator.new(booking_type: booking_type, from: from, to: to).call

        render json: AvailabilitySerializer.payload(booking_type: booking_type, days: days)
      rescue GoogleCalendar::Client::Error => e
        # Busy 時間が取れないまま枠を返すと、埋まっている時間を空きとして見せてしまう。
        Rails.logger.error("[slot-relay] 空き枠計算に失敗しました: #{e.message}")
        render_error(:calendar_error, "空き枠を取得できませんでした。時間をおいて再度お試しください。")
      end

      private

      def default_from
        Time.current.in_time_zone(booking_type.tz).to_date
      end

      def parse_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
