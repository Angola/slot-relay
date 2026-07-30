# frozen_string_literal: true

# Google OAuth の連携状態。連携アカウントは 1 つだけなので、実質シングルトンとして扱う。
#
# refresh token は平文で持たず、SECRET_KEY_BASE 由来の鍵で暗号化して保存する。
# ActiveRecord Encryption ではなく MessageEncryptor を使うのは、AR Encryption だと
# production 必須の環境変数が 3 本増えるため（経緯は
# docs/plans/2026-07-30-google-oauth-calendar-selection.md）。
#
# **SECRET_KEY_BASE を回すと復号できなくなり、再連携が必要になる**（docs/SECURITY.md）。
class GoogleConnection < ApplicationRecord
  # 鍵導出のラベル。変えると既存の暗号文が復号できなくなるので触らない。
  ENCRYPTION_PURPOSE = "slot-relay/google-oauth-refresh-token"

  validates :google_account_email, presence: true, uniqueness: true
  validates :encrypted_refresh_token, presence: true
  validates :connected_at, presence: true

  # 連携は 1 つだけ。無ければ nil。
  def self.current
    order(:id).first
  end

  def self.connected?
    current&.usable? || false
  end

  # 同意完了時に呼ぶ。既存の連携は上書きする（アカウントを変えたら差し替える）。
  def self.connect!(google_account_email:, refresh_token:, scopes:)
    transaction do
      # 単一行を保つため、別アカウントの行が残らないよう先に消す
      where.not(google_account_email: google_account_email).delete_all

      connection = find_or_initialize_by(google_account_email: google_account_email)
      connection.refresh_token = refresh_token
      connection.scopes = Array(scopes)
      connection.connected_at = Time.current
      connection.save!
      connection
    end
  end

  def self.disconnect!
    delete_all
  end

  def refresh_token=(value)
    @refresh_token = value
    self.encrypted_refresh_token = value.present? ? self.class.encryptor.encrypt_and_sign(value) : nil
  end

  # 復号できない（SECRET_KEY_BASE が変わった・データが壊れた）場合は nil を返す。
  # 例外にすると空き取得のたびに 500 になるため、「未連携」として扱えるようにする。
  def refresh_token
    return @refresh_token if defined?(@refresh_token) && @refresh_token.present?
    return nil if encrypted_refresh_token.blank?

    @refresh_token = self.class.encryptor.decrypt_and_verify(encrypted_refresh_token)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    Rails.logger.error(
      "[slot-relay] Google の refresh token を復号できません。" \
      "SECRET_KEY_BASE が変わった可能性があります。再連携が必要です。"
    )
    nil
  end

  # 実際に API を呼べる状態か。
  def usable?
    refresh_token.present?
  end

  # 要求したスコープがすべて同意されているか（ユーザーが一部だけ許可することがある）。
  def missing_scopes(required = GoogleCalendar::Client::SCOPES)
    Array(required) - Array(scopes)
  end

  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key(ENCRYPTION_PURPOSE, 32)
    )
  end

  # テスト用。SECRET_KEY_BASE を差し替えたときにメモ化を捨てる。
  def self.reset_encryptor!
    @encryptor = nil
  end
end
