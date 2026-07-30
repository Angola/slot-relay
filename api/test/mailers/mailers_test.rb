# frozen_string_literal: true

require "test_helper"

class MailersTest < ActionMailer::TestCase
  MONDAY = BookingFactories::MONDAY

  setup do
    @booking_type = create_booking_type
    @reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: jst(MONDAY, "10:00"))
  end

  test "予約確定メールは予約メニューのタイムゾーンで日時を書く" do
    mail = GuestMailer.reservation_confirmed(@reservation)

    assert_equal ["taro@example.com"], mail.to
    assert_equal ["info@example.com"], mail.from
    assert_equal "【無料相談】ご予約を承りました", mail.subject

    body = mail.body.to_s
    assert_includes body, "2026年8月3日(月) 10:00〜11:00"
    assert_includes body, "Asia/Tokyo"
    assert_includes body, @reservation.public_id
    assert_includes body, "株式会社サンプル"
  end

  test "予約確定メールにキャンセル URL を載せる" do
    body = GuestMailer.reservation_confirmed(@reservation).body.to_s

    assert_includes body, SlotRelay.config.cancel_url_for(@reservation.public_id, @reservation.cancel_token)
  end

  test "生トークンが手元に無いときはキャンセル URL を書かない" do
    reloaded = Reservation.find(@reservation.id)
    body = GuestMailer.reservation_confirmed(reloaded).body.to_s

    assert_not_includes body, "/c/"
    assert_not_includes body, reloaded.cancel_token_hash
  end

  test "キャンセルメール" do
    mail = GuestMailer.reservation_cancelled(@reservation)

    assert_includes mail.subject, "キャンセル"
    assert_includes mail.body.to_s, "2026年8月3日(月) 10:00〜11:00"
  end

  test "日時変更メールは変更前後を書く" do
    previous = jst(MONDAY, "10:00")
    @reservation.update!(start_at: jst(MONDAY, "14:00"), end_at: jst(MONDAY, "15:00"))

    body = GuestMailer.reservation_rescheduled(@reservation, previous).body.to_s

    assert_includes body, "変更前"
    assert_includes body, "2026年8月3日(月) 10:00"
    assert_includes body, "2026年8月3日(月) 14:00"
  end

  test "管理者向け新規予約通知には問い合わせ内容も入る" do
    @reservation.update!(answers: { "相談内容" => "日報業務を自動化したい" })
    mail = AdminMailer.reservation_created(@reservation)

    assert_equal ["admin@example.com"], mail.to
    assert_includes mail.subject, "[新規予約]"
    assert_includes mail.body.to_s, "日報業務を自動化したい"
    assert_includes mail.body.to_s, "taro@example.com"
  end

  test "カレンダー連携エラー通知にはエラー内容と対応の目安を書く" do
    mail = AdminMailer.calendar_error(@reservation, "insufficientPermissions")

    assert_includes mail.subject, "[要対応]"
    assert_includes mail.body.to_s, "insufficientPermissions"
    assert_includes mail.body.to_s, @reservation.public_id
  end

  test "ADMIN_NOTIFICATION_EMAIL が未設定なら管理者メールを送らない" do
    configure_slot_relay!(admin_notification_email: nil)

    assert_nothing_raised { AdminMailer.reservation_created(@reservation).deliver_now }
    assert_empty ActionMailer::Base.deliveries
  end
end
