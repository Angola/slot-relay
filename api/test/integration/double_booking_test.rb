# frozen_string_literal: true

require "test_helper"

# 二重予約防止のテスト。
#
# 予約 API の核心はここなので、DB の排他制約が本当に同時リクエストを直列化するかを
# 実スレッド（別コネクション）で確かめる。
#
# テストをトランザクションで包むと、他スレッドの別コネクションから
# セットアップしたデータが見えないため、ここだけ無効にして手動で掃除する。
class DoubleBookingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  MONDAY = BookingFactories::MONDAY
  CONCURRENCY = 5

  setup do
    @booking_type = create_booking_type
    @start_at = jst(MONDAY, "10:00")
  end

  teardown do
    Reservation.delete_all
    WeeklyAvailability.delete_all
    AvailabilityOverride.delete_all
    BookingTypeOrigin.delete_all
    BookingType.delete_all
  end

  test "同じ枠へ同時に予約しても 1 件だけ成立する" do
    freeze_base_time do
      results = run_concurrently(CONCURRENCY) { |index| create_reservation(index, idempotency_key: "key-#{index}") }

      succeeded = results.select(&:success?)
      failed = results.select(&:failure?)

      assert_equal 1, succeeded.size, "同時予約が複数成立した: #{results.map(&:code).inspect}"
      assert_equal CONCURRENCY - 1, failed.size
      assert(failed.all? { |result| result.code == :slot_unavailable },
             "想定外の失敗理由: #{failed.map(&:code).inspect}")

      assert_equal 1, Reservation.confirmed.count
      assert_equal 1, Reservation.count
    end
  end

  # 同じ Idempotency-Key の同時リクエストは「二重予約」ではなく「再送」として扱う。
  # 先着の予約が返るか、まだ処理中なら REQUEST_IN_PROGRESS になり、
  # SLOT_UNAVAILABLE にはならない（同じキーなので枠の競合ではない）。
  test "同じ Idempotency-Key で同時に来ても予約は 1 件で、同じ予約が返る" do
    freeze_base_time do
      results = run_concurrently(CONCURRENCY) { |index| create_reservation(index, idempotency_key: "same-key") }

      assert_equal 1, Reservation.count,
                   Reservation.pluck(:status, :idempotency_key, :start_at).inspect
      reservation = Reservation.sole

      assert_predicate reservation, :confirmed?
      assert_equal ["same-key"], results.filter_map { |r| r.value&.idempotency_key }.uniq
      assert(results.select(&:success?).all? { |r| r.value.id == reservation.id })
      assert(results.select(&:failure?).all? { |r| r.code == :request_in_progress },
             "想定外の失敗理由: #{results.select(&:failure?).map(&:code).inspect}")
    end
  end

  test "異なる枠への同時予約はすべて成立する" do
    freeze_base_time do
      results = run_concurrently(CONCURRENCY) do |index|
        create_reservation(index, idempotency_key: "key-#{index}", start_at: @start_at + index.hours)
      end

      assert_equal CONCURRENCY, results.count(&:success?), results.map(&:message).inspect
      assert_equal CONCURRENCY, Reservation.confirmed.count
    end
  end

  private

  def create_reservation(index, idempotency_key:, start_at: @start_at)
    Reservations::Creator.new(
      booking_type: BookingType.find(@booking_type.id),
      params: {
        start_at: start_at.iso8601,
        guest_name: "予約者#{index}",
        guest_email: "guest#{index}@example.com",
        guest_company: "株式会社サンプル",
        answers: {}
      },
      idempotency_key: idempotency_key,
      # スレッドごとに別インスタンスにして、Fake 側の配列への同時書き込みを避ける
      calendar_client: FakeCalendarClient.new
    ).call
  end

  # 全スレッドを揃えてから一斉に走らせる。ActiveRecord のコネクションはスレッドごとに
  # 独立するため、DB レベルの排他制約が実際に働くかを確認できる。
  def run_concurrently(count, &block)
    mutex = Mutex.new
    condition = ConditionVariable.new
    ready = 0

    threads = Array.new(count) do |index|
      Thread.new do
        mutex.synchronize do
          ready += 1
          condition.broadcast
          condition.wait(mutex) while ready < count
        end

        ActiveRecord::Base.connection_pool.with_connection { block.call(index) }
      end
    end

    threads.map(&:value)
  end
end
