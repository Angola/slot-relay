# frozen_string_literal: true

require "test_helper"

class TurnstileVerifierTest < ActiveSupport::TestCase
  test "シークレット未設定なら検証をスキップする" do
    configure_slot_relay!(turnstile_secret_key: nil)
    verifier = TurnstileVerifier.new

    assert_not_predicate verifier, :enabled?
    assert verifier.verify(nil)
    assert verifier.verify("anything")
  end

  test "success: true なら通す" do
    configure_slot_relay!(turnstile_secret_key: "secret")
    stub = stub_request(:post, TurnstileVerifier::VERIFY_URL)
           .with(body: hash_including("secret" => "secret", "response" => "token", "remoteip" => "203.0.113.10"))
           .to_return(status: 200, body: { success: true }.to_json)

    assert TurnstileVerifier.new.verify("token", remote_ip: "203.0.113.10")
    assert_requested stub
  end

  test "success: false なら弾く" do
    configure_slot_relay!(turnstile_secret_key: "secret")
    stub_request(:post, TurnstileVerifier::VERIFY_URL)
      .to_return(status: 200, body: { success: false, "error-codes" => ["invalid-input-response"] }.to_json)

    assert_not TurnstileVerifier.new.verify("token")
  end

  test "トークンが空なら通信せず弾く" do
    configure_slot_relay!(turnstile_secret_key: "secret")

    assert_not TurnstileVerifier.new.verify(nil)
    assert_not TurnstileVerifier.new.verify("")
    assert_not_requested :post, TurnstileVerifier::VERIFY_URL
  end

  test "Cloudflare 側の障害では弾く（fail closed）" do
    configure_slot_relay!(turnstile_secret_key: "secret")
    stub_request(:post, TurnstileVerifier::VERIFY_URL).to_timeout

    assert_not TurnstileVerifier.new.verify("token")
  end

  test "壊れた JSON でも例外を投げず弾く" do
    configure_slot_relay!(turnstile_secret_key: "secret")
    stub_request(:post, TurnstileVerifier::VERIFY_URL).to_return(status: 200, body: "<html>error</html>")

    assert_not TurnstileVerifier.new.verify("token")
  end
end
