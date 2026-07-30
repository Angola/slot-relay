# frozen_string_literal: true

require "test_helper"

module GoogleOauth
  class SetupSessionTest < ActiveSupport::TestCase
    test "発行したトークンは有効" do
      assert SetupSession.valid?(SetupSession.issue)
    end

    test "改ざん・空のトークンは無効" do
      assert_not SetupSession.valid?(nil)
      assert_not SetupSession.valid?("")
      assert_not SetupSession.valid?("#{SetupSession.issue}x")
    end

    test "30 分で失効する" do
      token = SetupSession.issue

      travel(SetupSession::TTL + 1.minute) do
        assert_not SetupSession.valid?(token)
      end
    end

    test "CSRF トークンは発行元のセッションでのみ有効" do
      session = SetupSession.issue
      csrf = SetupSession.csrf_token_for(session)

      assert SetupSession.valid_csrf?(session, csrf)
    end

    test "別セッションの CSRF トークンは通らない" do
      session_a = SetupSession.issue
      session_b = SetupSession.issue

      assert_not SetupSession.valid_csrf?(session_a, SetupSession.csrf_token_for(session_b))
    end

    test "CSRF トークンが無い・壊れている場合は通らない" do
      session = SetupSession.issue

      assert_not SetupSession.valid_csrf?(session, nil)
      assert_not SetupSession.valid_csrf?(session, "")
      assert_not SetupSession.valid_csrf?(session, "deadbeef")
    end

    test "セッショントークンをそのまま CSRF トークンとして使い回せない（purpose が違う）" do
      session = SetupSession.issue

      assert_not SetupSession.valid_csrf?(session, session)
    end

    test "Cookie は HttpOnly / SameSite=Strict で、パスが設定画面に限定される" do
      options = SetupSession.cookie_options

      assert options[:httponly]
      assert_equal :strict, options[:same_site]
      assert_equal "/v1/admin/google", options[:path]
    end
  end
end
