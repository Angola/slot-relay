# frozen_string_literal: true

module GoogleCalendar
  # Google 連携が使えない状態（未設定・未連携・トークン復号不能）のときに返すクライアント。
  #
  # NullClient のように黙って空を返すと **Busy 時間が空 = 全部空き**として予約を受けてしまう。
  # 本番ではそれを避けるため、呼ばれた時点で Client::Error にして 502 を返させる。
  class UnavailableClient
    def initialize(reason)
      @reason = reason
    end

    def busy_periods(**_options)
      fail_with("空き時間を取得")
    end

    def create_event(**_options)
      fail_with("予定を作成")
    end

    def delete_event(**_options)
      fail_with("予定を削除")
    end

    def calendars
      fail_with("カレンダー一覧を取得")
    end

    private

    def fail_with(action)
      raise Client::Error, "Google カレンダーに接続できないため#{action}できません: #{@reason}"
    end
  end
end
