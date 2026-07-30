# frozen_string_literal: true

# Google OAuth の連携状態。連携アカウントは 1 つだけなので単一行で持つ
# （複数行にならないよう部分ユニークインデックスで縛る）。
class CreateGoogleConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :google_connections do |t|
      # 連携した Google アカウント。primary カレンダーの ID を使う（= メールアドレス）
      t.string :google_account_email, null: false
      # refresh token は SECRET_KEY_BASE 由来の鍵で暗号化して入れる（平文では保存しない）
      t.text   :encrypted_refresh_token, null: false
      # 同意で実際に得られたスコープ。要求と食い違ったら画面で警告する
      t.string :scopes, null: false, array: true, default: []
      t.datetime :connected_at, null: false

      t.timestamps
    end

    # 単一行であることを DB でも保証する
    add_index :google_connections, :google_account_email, unique: true
  end
end
