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
