# frozen_string_literal: true

require "test_helper"

module Reservations
  class CreatorTest < ActiveSupport::TestCase
    MONDAY = BookingFactories::MONDAY

    setup do
      @booking_type = create_booking_type
      @start_at = jst(MONDAY, "10:00")
    end

    test "予約を確定し Google カレンダーへ予定を作る" do
      freeze_base_time do
        result = create

        assert_predicate result, :success?
        reservation = result.value

        assert_predicate reservation, :confirmed?
        assert_equal @start_at, reservation.start_at
        assert_equal @start_at + 1.hour, reservation.end_at
        assert_nil reservation.expires_at

        assert_equal 1, fake_calendar.created_events.size
        event = fake_calendar.created_events.first
        assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, event[:calendar_id]
        assert_equal reservation.google_event_id, event[:id]
        assert_equal "【無料相談】株式会社サンプル / 山田太郎", event[:summary]
        assert_includes event[:description], reservation.public_id
        assert_includes event[:description], "日報業務を自動化したい"
        assert_equal reservation.public_id, event[:private_properties]["slotRelayReservationId"]
      end
    end

    test "予約者と管理者へメールを送る" do
      freeze_base_time do
        create

        assert_equal 2, ActionMailer::Base.deliveries.size
        to_guest, to_admin = ActionMailer::Base.deliveries

        assert_equal ["taro@example.com"], to_guest.to
        assert_includes to_guest.subject, "ご予約を承りました"
        assert_includes to_guest.body.to_s, "2026年8月3日(月) 10:00〜11:00"

        assert_equal ["admin@example.com"], to_admin.to
        assert_includes to_admin.subject, "[新規予約]"
      end
    end

    test "確認メールにキャンセル URL（生トークン）を載せる" do
      freeze_base_time do
        reservation = create.value
        body = ActionMailer::Base.deliveries.first.body.to_s

        assert_includes body, reservation.public_id
        assert_match %r{https://booking-api\.example\.com/c/#{reservation.public_id}/\S+}, body
        assert_not_includes body, reservation.cancel_token_hash
      end
    end

    test "Idempotency-Key が無いと拒否する" do
      freeze_base_time do
        result = create(idempotency_key: nil)

        assert_predicate result, :failure?
        assert_equal :validation_failed, result.code
        assert_equal 0, Reservation.count
      end
    end

    test "同じ Idempotency-Key の再送では予約を増やさない" do
      freeze_base_time do
        first = create(idempotency_key: "key-1")
        second = create(idempotency_key: "key-1")

        assert_predicate second, :success?
        assert_equal first.value.id, second.value.id
        assert_equal 1, Reservation.count
        assert_equal 1, fake_calendar.created_events.size
      end
    end

    test "別の Idempotency-Key・同じ枠は 409 SLOT_UNAVAILABLE" do
      freeze_base_time do
        create(idempotency_key: "key-1")
        result = create(idempotency_key: "key-2")

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
        assert_equal 1, Reservation.confirmed.count
      end
    end

    test "Google カレンダーに予定がある枠は予約できない" do
      fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID, [[@start_at, @start_at + 1.hour]])

      freeze_base_time do
        result = create

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
        # 仮確保は解除されている
        assert_equal 0, Reservation.count
        assert_empty fake_calendar.created_events
      end
    end

    test "受付時間外の枠は予約できない" do
      freeze_base_time do
        result = create(start_at: jst(MONDAY, "20:00"))

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
      end
    end

    test "枠の境界に一致しない開始時刻は予約できない" do
      freeze_base_time do
        result = create(start_at: jst(MONDAY, "10:30"))

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
      end
    end

    test "最短受付時間より前の枠は予約できない" do
      freeze_base_time do
        # 基準時刻 7/30 09:00 の 1 時間後
        result = create(start_at: jst(Date.new(2026, 7, 30), "10:00"))

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
      end
    end

    test "startAt の形式が不正なら 422" do
      freeze_base_time do
        ["", "not-a-time", nil].each do |value|
          result = build_creator(params: reservation_params.merge(start_at: value)).call

          assert_predicate result, :failure?
          assert_equal :invalid_start_at, result.code
        end
      end
    end

    test "入力が不正なら 422 で詳細を返す" do
      freeze_base_time do
        result = build_creator(params: reservation_params.merge(guest_email: "bad")).call

        assert_predicate result, :failure?
        assert_equal :validation_failed, result.code
        assert_predicate result.details, :present?
        assert_equal 0, Reservation.count
      end
    end

    test "Google 予定の作成に失敗したら failed にし枠を解放する" do
      fake_calendar.raise_on_create = true

      freeze_base_time do
        result = create

        assert_predicate result, :failure?
        assert_equal :calendar_error, result.code

        reservation = Reservation.sole
        assert_predicate reservation, :failed?
        assert_nil reservation.expires_at

        # 管理者へエラー通知が飛ぶ／予約者へは何も送らない
        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes ActionMailer::Base.deliveries.first.subject, "[要対応]"

        # failed は排他制約の対象外なので同じ枠を予約し直せる
        fake_calendar.raise_on_create = false
        retry_result = create(idempotency_key: "key-retry")
        assert_predicate retry_result, :success?
      end
    end

    test "メール送信に失敗しても予約は成立させる" do
      freeze_base_time do
        with_failing_mail do
          result = create

          assert_predicate result, :success?
          assert_predicate result.value, :confirmed?
          assert_predicate Reservation.sole, :confirmed?
        end
      end
    end

    test "Turnstile を有効にするとトークン無しは拒否される" do
      configure_slot_relay!(turnstile_secret_key: "secret")
      stub_turnstile(success: false)

      freeze_base_time do
        result = create

        assert_predicate result, :failure?
        assert_equal :turnstile_failed, result.code
        assert_equal 0, Reservation.count
      end
    end

    # Turnstile のトークンは 1 回しか検証できない。応答を取りこぼしたクライアントが
    # 同じキー・同じトークンで再送したとき、TURNSTILE_FAILED ではなく既存予約が返ること。
    test "同じ Idempotency-Key の再送は Turnstile を再検証せず既存予約を返す" do
      configure_slot_relay!(turnstile_secret_key: "secret")
      stub_turnstile(success: true)

      freeze_base_time do
        first = create(idempotency_key: "key-1", params: reservation_params.merge(turnstile_token: "token"))
        assert_predicate first, :success?

        # 2 回目の siteverify は timeout-or-duplicate で失敗する
        stub_turnstile(success: false)

        second = create(idempotency_key: "key-1", params: reservation_params.merge(turnstile_token: "token"))

        assert_predicate second, :success?
        assert_equal first.value.id, second.value.id
        assert_equal 1, Reservation.count
      end
    end

    test "同じ枠の別メニューが先に押さえていたら 409（登録先カレンダーが同じ場合）" do
      other = create_booking_type(slug: "other-menu")

      freeze_base_time do
        create_confirmed_reservation(booking_type: other, start_at: @start_at, guest_email: "other@example.com")

        result = create

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
      end
    end

    test "予約には登録先カレンダーが記録される" do
      freeze_base_time do
        assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, create.value.booking_calendar_id
      end
    end

    test "Turnstile の検証が通れば予約できる" do
      configure_slot_relay!(turnstile_secret_key: "secret")
      stub_turnstile(success: true)

      freeze_base_time do
        result = create(params: reservation_params.merge(turnstile_token: "token"))

        assert_predicate result, :success?
      end
    end

    test "期限切れの仮確保は掃除して予約できる" do
      freeze_base_time do
        @booking_type.reservations.create!(
          start_at: @start_at, end_at: @start_at + 1.hour,
          guest_name: "放置", guest_email: "old@example.com",
          status: "pending", expires_at: 10.minutes.ago, idempotency_key: "stale"
        )

        result = create

        assert_predicate result, :success?
        assert_equal 1, Reservation.count
      end
    end

    test "answers は文字列マップとして保存される" do
      freeze_base_time do
        reservation = create.value

        assert_equal({ "相談内容" => "日報業務を自動化したい" }, reservation.answers)
      end
    end

    private

    def reservation_params(start_at: @start_at)
      {
        start_at: start_at.is_a?(String) ? start_at : start_at.iso8601,
        guest_name: "山田太郎",
        guest_email: "taro@example.com",
        guest_company: "株式会社サンプル",
        guest_phone: "090-0000-0000",
        answers: { "相談内容" => "日報業務を自動化したい" },
        turnstile_token: nil
      }
    end

    def build_creator(params:, idempotency_key: "key-default")
      Creator.new(
        booking_type: @booking_type,
        params: params,
        idempotency_key: idempotency_key,
        remote_ip: "203.0.113.10",
        calendar_client: fake_calendar
      )
    end

    def create(start_at: @start_at, idempotency_key: "key-default", params: nil)
      build_creator(params: params || reservation_params(start_at: start_at),
                    idempotency_key: idempotency_key).call
    end

    def stub_turnstile(success:)
      stub_request(:post, TurnstileVerifier::VERIFY_URL)
        .to_return(status: 200, body: { success: success }.to_json, headers: { "Content-Type" => "application/json" })
    end
  end
end
