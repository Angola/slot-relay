# frozen_string_literal: true

# Google カレンダーに作る予定の件名・説明文（docs/DESIGN.md §6.2）。
#
#   件名: 【無料相談】株式会社サンプル / 山田太郎
#   説明: 予約 ID・会社名・氏名・メール・電話番号・相談内容
module GoogleEventPresenter
  module_function

  def summary(reservation)
    who = [reservation.guest_company.presence, reservation.guest_name].compact.join(" / ")
    "【#{reservation.booking_type.name}】#{who}"
  end

  def description(reservation)
    lines = [
      "予約ID: #{reservation.public_id}",
      ("会社名: #{reservation.guest_company}" if reservation.guest_company.present?),
      "氏名: #{reservation.guest_name}",
      "メール: #{reservation.guest_email}",
      ("電話番号: #{reservation.guest_phone}" if reservation.guest_phone.present?)
    ].compact

    reservation.answers.each do |key, value|
      lines << ""
      lines << "#{key}:"
      lines << value.to_s
    end

    lines.join("\n")
  end
end
