# frozen_string_literal: true

# 運用エンドポイント。
#
#   GET /health — liveness。プロセスが生きているかだけを見る（Coolify のヘルスチェック用）
#   GET /ready  — readiness。DB へ実際に接続できるかまで見る
#
# /health で DB を触らないのは、DB 一時障害でコンテナが再起動ループに入るのを避けるため。
class HealthController < ApplicationController
  def show
    render json: { status: "ok", version: SlotRelay::VERSION }
  end

  def ready
    ActiveRecord::Base.connection.select_value("SELECT 1")
    render json: { status: "ready", database: "ok" }
  rescue StandardError => e
    Rails.logger.error("[slot-relay] readiness チェック失敗: #{e.class}: #{e.message}")
    render json: { status: "unavailable", database: "error" }, status: 503
  end
end
