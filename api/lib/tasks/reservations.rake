# frozen_string_literal: true

namespace :reservations do
  desc "期限切れの仮確保（pending）を削除する"
  # 予約作成時にも掃除しているので必須ではないが、予約が来ない期間に残り続けるのを防ぐ。
  # cron で 1 日 1 回程度回せば足りる（docs/DEPLOY.md）。
  task sweep_expired_pending: :environment do
    deleted = Reservation.expired_pending.delete_all
    puts "期限切れの仮確保を #{deleted} 件削除しました"
  end

  desc "予約の状態を集計して表示する"
  task stats: :environment do
    Reservation.group(:status).count.sort.each { |status, count| puts "#{status}: #{count}" }
  end
end
