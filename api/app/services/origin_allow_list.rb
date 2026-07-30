# frozen_string_literal: true

# 全予約メニューの許可 Origin をまとめた集合。CORS プリフライト（OPTIONS）の判定に使う。
#
# プリフライトはリクエスト本体を持たず、URL から予約メニューを引くのは脆いため、
# ここでは「どこかの予約メニューが許可している Origin か」だけを見る。
# 予約メニュー単位の厳密な検証は本リクエスト側（PublicApi#verify_origin!）で行う。
module OriginAllowList
  CACHE_TTL = 30.seconds

  class << self
    def allowed?(origin)
      return false if origin.blank?

      origins.include?(origin)
    end

    def origins
      mutex.synchronize do
        if @origins.nil? || @loaded_at.nil? || @loaded_at < Time.current - CACHE_TTL
          @origins = BookingTypeOrigin.distinct.pluck(:origin).to_set
          @loaded_at = Time.current
        end

        @origins
      end
    rescue ActiveRecord::ActiveRecordError => e
      # DB が落ちていても CORS 判定でアプリ全体を落とさない（本リクエスト側で 404/503 になる）
      Rails.logger.error("[slot-relay] 許可 Origin の読み込みに失敗しました: #{e.class}")
      Set.new
    end

    def reset!
      mutex.synchronize do
        @origins = nil
        @loaded_at = nil
      end
    end

    private

    def mutex
      @mutex ||= Mutex.new
    end
  end
end
