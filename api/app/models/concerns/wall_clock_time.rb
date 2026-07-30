# frozen_string_literal: true

# PostgreSQL の `time` 型カラムを「予約メニューのタイムゾーンにおける壁時計時刻」として扱う。
#
# `time` カラムは ActiveRecord 上ではダミー日付付きの Time になり、そのまま日付と
# 組み合わせるとタイムゾーンを取り違えやすい。この concern は値を
# **深夜 0 時からの分数**（`*_minutes`）と **"HH:MM" 文字列**（`*_hhmm`）としてだけ
# 露出させ、日付との合成は AvailabilityCalculator 側に閉じ込める。
module WallClockTime
  extend ActiveSupport::Concern

  HHMM = /\A([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\z/

  class_methods do
    def wall_clock_time(*attribute_names)
      attribute_names.each do |name|
        define_method(:"#{name}=") do |value|
          super(WallClockTime.normalize(value))
        end

        define_method(:"#{name}_minutes") do
          WallClockTime.to_minutes(public_send(name))
        end

        define_method(:"#{name}_hhmm") do
          minutes = public_send(:"#{name}_minutes")
          minutes && format("%02d:%02d", minutes / 60, minutes % 60)
        end
      end

      # start_time / end_time の組を前提にした短縮形
      define_method(:start_minutes) { start_time_minutes } if attribute_names.include?(:start_time)
      define_method(:end_minutes) { end_time_minutes } if attribute_names.include?(:end_time)
    end
  end

  # "10:00" / "10:00:00" だけを受け付ける。壊れた文字列は nil にして
  # presence バリデーションでエラーにする（黙って 00:00 に丸めない）。
  def self.normalize(value)
    case value
    when nil then nil
    when String
      value.strip.match(HHMM) ? value.strip : nil
    else
      value
    end
  end

  def self.to_minutes(value)
    return nil if value.nil?

    (value.hour * 60) + value.min
  end
end
