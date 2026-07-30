# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# 外部 HTTP 通信（Google Calendar / Turnstile）はテストから一切出さない。
WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    include SlotRelayTestConfig
    include BookingFactories
    include FailingMailHelper

    setup do
      # レートリミットはテストごとに状態を持ち越さないよう既定で無効。
      # 検証するテストだけが with_rack_attack で有効化する。
      Rack::Attack.enabled = false
      Rack::Attack.cache.store.clear

      configure_slot_relay!
      SlotRelay.calendar_client = FakeCalendarClient.new
      OriginAllowList.reset!
      ActionMailer::Base.deliveries.clear
    end

    teardown do
      SlotRelay.reset!
      Rack::Attack.enabled = false
    end

    def fake_calendar
      SlotRelay.calendar_client
    end

    def with_rack_attack
      Rack::Attack.enabled = true
      Rack::Attack.cache.store.clear
      yield
    ensure
      Rack::Attack.enabled = false
    end
  end
end
