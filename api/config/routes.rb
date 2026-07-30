Rails.application.routes.draw do
  # 運用エンドポイント（Coolify のヘルスチェックは /health を見る）
  get "health" => "health#show"
  get "ready" => "health#ready"
  get "up" => "health#show" # Rails 既定のヘルスチェックパスも同じ扱いにする

  # API 仕様
  get "openapi.json" => "docs#openapi", defaults: { format: :json }, as: :openapi
  get "docs" => "docs#index"

  namespace :v1 do
    # 公開 API — 予約サイトのブラウザから呼ぶ。秘密の API キーは使わない。
    namespace :public do
      get  "booking-types/:slug"               => "booking_types#show", as: :booking_type
      get  "booking-types/:slug/availability"  => "availability#index", as: :booking_type_availability
      post "booking-types/:slug/reservations"  => "reservations#create", as: :booking_type_reservations

      get  "reservations/:public_token"        => "reservations#show", as: :reservation
      post "reservations/:public_token/cancel" => "reservations#cancel", as: :cancel_reservation

      # CORS プリフライト
      match "*path" => "preflight#handle", via: :options
    end

    # 管理 API — X-Admin-Key 必須
    namespace :admin do
      # Google 連携。コールバックだけは Google からのリダイレクトなので
      # X-Admin-Key を付けられず、state の署名で正当性を確認する。
      # 設定画面（setup）は同意直後の短期セッション Cookie でも開ける。
      post "google/oauth/url"      => "google_oauth#create_url", as: :google_oauth_url
      get  "google/oauth/callback" => "google_oauth#callback", as: :google_oauth_callback
      get  "google/calendars"      => "google_calendars#index", as: :google_calendars
      get  "google/setup"          => "google_setup#show", as: :google_setup
      post "google/setup"          => "google_setup#update"
      # ブラウザだけで完結させるための導線（管理キーはフォームの POST ボディで送る）
      post "google/login"          => "google_setup#login", as: :google_login
      post "google/connect"        => "google_setup#connect", as: :google_connect
      post "google/disconnect"     => "google_setup#disconnect", as: :google_disconnect

      resources :booking_types, path: "booking-types", only: %i[index create show update destroy]

      resources :reservations, only: %i[index show] do
        member do
          post :cancel
          post :reschedule
        end
      end
    end
  end
end
