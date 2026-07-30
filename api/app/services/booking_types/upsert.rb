# frozen_string_literal: true

module BookingTypes
  # 管理 API から予約メニューを登録・更新する。
  #
  # リクエストは camelCase（外部サイトの JS と揃えるため）なので、ここで属性名へ写す。
  # PATCH では「送られたキーだけ」を更新し、ネストしたコレクション
  # （allowedOrigins / weeklyAvailability / availabilityOverrides）はキーがあれば全置換する。
  # 差分マージにしないのは、曜日別受付時間の部分更新は表現が曖昧でミスを招きやすいため。
  class Upsert
    ATTRIBUTE_MAP = {
      "name" => :name,
      "slug" => :slug,
      "description" => :description,
      "durationMinutes" => :duration_minutes,
      "timeZone" => :time_zone,
      "minimumNoticeMinutes" => :minimum_notice_minutes,
      "bookingWindowDays" => :booking_window_days,
      "bufferBeforeMinutes" => :buffer_before_minutes,
      "bufferAfterMinutes" => :buffer_after_minutes,
      "googleBookingCalendarId" => :google_booking_calendar_id,
      "status" => :status
    }.freeze

    MAX_COLLECTION_SIZE = 200

    def initialize(booking_type:, payload:)
      @booking_type = booking_type
      @payload = payload.to_h.stringify_keys
      @errors = []
    end

    # @return [ServiceResult] 成功時 value は BookingType
    def call
      booking_type.assign_attributes(mapped_attributes)

      BookingType.transaction do
        raise ActiveRecord::Rollback unless save_booking_type
        raise ActiveRecord::Rollback unless replace_collections
      end

      return ServiceResult.failure(:validation_failed, "入力内容に誤りがあります。", details: errors) if errors.any?

      ServiceResult.success(booking_type.reload)
    end

    private

    attr_reader :booking_type, :payload, :errors

    def mapped_attributes
      ATTRIBUTE_MAP.filter_map { |json_key, attribute|
        [attribute, payload[json_key]] if payload.key?(json_key)
      }.to_h
    end

    def save_booking_type
      return true if booking_type.save

      errors.concat(booking_type.errors.full_messages)
      false
    end

    def replace_collections
      replace_origins && replace_weekly_availability && replace_overrides
    end

    def replace_origins
      return true unless payload.key?("allowedOrigins")

      values = array_payload("allowedOrigins")
      return false if values.nil?

      booking_type.origins.destroy_all
      values.each_with_index do |origin, index|
        record = booking_type.origins.build(origin: origin.is_a?(String) ? origin : nil)
        next if record.save

        add_errors("allowedOrigins[#{index}]", record)
        return false
      end

      OriginAllowList.reset!
      true
    end

    def replace_weekly_availability
      return true unless payload.key?("weeklyAvailability")

      entries = array_payload("weeklyAvailability")
      return false if entries.nil?

      booking_type.weekly_availabilities.destroy_all
      entries.each_with_index do |entry, index|
        entry = entry.to_h.stringify_keys if entry.respond_to?(:to_h)
        record = booking_type.weekly_availabilities.build(
          day_of_week: entry["dayOfWeek"],
          start_time: entry["startTime"],
          end_time: entry["endTime"]
        )
        next if record.save

        add_errors("weeklyAvailability[#{index}]", record)
        return false
      end

      true
    end

    def replace_overrides
      return true unless payload.key?("availabilityOverrides")

      entries = array_payload("availabilityOverrides")
      return false if entries.nil?

      booking_type.availability_overrides.destroy_all
      entries.each_with_index do |entry, index|
        entry = entry.to_h.stringify_keys if entry.respond_to?(:to_h)
        record = booking_type.availability_overrides.build(
          date: entry["date"],
          is_available: ActiveModel::Type::Boolean.new.cast(entry["isAvailable"]) || false,
          start_time: entry["startTime"],
          end_time: entry["endTime"]
        )
        next if record.save

        add_errors("availabilityOverrides[#{index}]", record)
        return false
      end

      true
    end

    def array_payload(key)
      value = payload[key]

      unless value.is_a?(Array)
        errors << "#{key} は配列で指定してください"
        return nil
      end

      if value.size > MAX_COLLECTION_SIZE
        errors << "#{key} の要素数が多すぎます（最大 #{MAX_COLLECTION_SIZE}）"
        return nil
      end

      value
    end

    def add_errors(prefix, record)
      record.errors.full_messages.each { |message| errors << "#{prefix}: #{message}" }
    end
  end
end
