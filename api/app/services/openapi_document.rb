# frozen_string_literal: true

# OpenAPI 3.1 ドキュメント。gem で生成せず手書きしているのは、
# レスポンスの実体（*Serializer）と 1 対 1 で目視確認できるようにするため。
#
# 秘密情報（管理キー・Google 秘密鍵・SMTP 認証情報）は example にも含めない（docs/SECURITY.md）。
module OpenapiDocument
  module_function

  def as_json
    {
      openapi: "3.1.0",
      info: {
        title: "slot-relay 予約 API",
        version: SlotRelay::VERSION,
        description: <<~MD
          Google カレンダー連携の予約 API。

          - **公開 API**（`/v1/public/...`）は予約サイトのブラウザから呼ぶ。秘密の API キーは使わない。
            許可 Origin の検証・レートリミット・Turnstile・Idempotency-Key で保護する。
          - **管理 API**（`/v1/admin/...`）は `X-Admin-Key` ヘッダで認証する。

          時刻はすべて RFC 3339。空き枠・予約の時刻は予約メニューのタイムゾーンのオフセット付きで返す。
        MD
      },
      servers: [{ url: SlotRelay.config.public_base_url }],
      tags: [
        { name: "public", description: "予約サイトから呼ぶ公開 API" },
        { name: "admin", description: "管理 API（X-Admin-Key 必須）" },
        { name: "ops", description: "運用エンドポイント" }
      ],
      paths: paths,
      components: components
    }
  end

  def paths
    {
      "/health" => {
        get: {
          tags: ["ops"], summary: "liveness", operationId: "health",
          responses: { "200" => json_response("稼働中", ref("HealthStatus")) }
        }
      },
      "/ready" => {
        get: {
          tags: ["ops"], summary: "readiness（DB 接続まで確認）", operationId: "ready",
          responses: {
            "200" => json_response("利用可能", ref("ReadyStatus")),
            "503" => json_response("DB へ接続できない", ref("ReadyStatus"))
          }
        }
      },
      "/v1/public/booking-types/{slug}" => {
        get: {
          tags: ["public"], summary: "予約メニューの公開情報を取得", operationId: "getPublicBookingType",
          parameters: [slug_param],
          responses: {
            "200" => json_response("予約メニュー", ref("PublicBookingType")),
            "403" => error_response("許可されていない Origin"),
            "404" => error_response("予約メニューが存在しない、または受付停止中")
          }
        }
      },
      "/v1/public/booking-types/{slug}/availability" => {
        get: {
          tags: ["public"], summary: "空き枠を取得", operationId: "getAvailability",
          description: "Google カレンダーに予定がある枠と、既存の有効な予約と重なる枠は返さない。" \
                       "枠が 0 件の日も `slots: []` で含める。",
          parameters: [
            slug_param,
            { name: "from", in: "query", required: false, description: "取得開始日（予約メニューのタイムゾーン）",
              schema: { type: "string", format: "date" }, example: "2026-08-01" },
            { name: "to", in: "query", required: false, description: "取得終了日（含む・最大 62 日間）",
              schema: { type: "string", format: "date" }, example: "2026-08-07" }
          ],
          responses: {
            "200" => json_response("空き枠", ref("Availability")),
            "400" => error_response("期間の指定が不正（INVALID_RANGE）"),
            "403" => error_response("許可されていない Origin"),
            "404" => error_response("予約メニューが存在しない"),
            "502" => error_response("Google カレンダーから Busy 時間を取得できない（CALENDAR_ERROR）")
          }
        }
      },
      "/v1/public/booking-types/{slug}/reservations" => {
        post: {
          tags: ["public"], summary: "予約を登録", operationId: "createReservation",
          description: "DB へ pending 予約を作って枠を仮確保し、Google FreeBusy で直前確認したうえで " \
                       "Google カレンダーへ予定を作成する。同じ枠への同時予約は 409 SLOT_UNAVAILABLE。",
          parameters: [slug_param, idempotency_key_param],
          requestBody: {
            required: true,
            content: { "application/json" => { schema: ref("CreateReservationRequest") } }
          },
          responses: {
            "201" => json_response("予約確定", ref("ReservationWithCancelUrl")),
            "403" => error_response("Turnstile 検証失敗（TURNSTILE_FAILED）または Origin 不許可"),
            "409" => error_response("枠が埋まっている（SLOT_UNAVAILABLE）／" \
                                    "同じ Idempotency-Key の処理中（REQUEST_IN_PROGRESS）"),
            "422" => error_response("入力不正（VALIDATION_FAILED / INVALID_START_AT）"),
            "429" => error_response("レートリミット超過"),
            "502" => error_response("Google カレンダーへの登録失敗（CALENDAR_ERROR）")
          }
        }
      },
      "/v1/public/reservations/{publicToken}" => {
        get: {
          tags: ["public"], summary: "予約を照会（キャンセルトークン）", operationId: "getReservation",
          description: "確認メールに記載したトークンを知っている人だけが参照できる。",
          parameters: [public_token_param],
          responses: {
            "200" => json_response("予約", ref("Reservation")),
            "404" => error_response("トークンが不正")
          }
        }
      },
      "/v1/public/reservations/{publicToken}/cancel" => {
        post: {
          tags: ["public"], summary: "予約をキャンセル", operationId: "cancelReservation",
          description: "DB を cancelled にし、Google カレンダーの予定も削除する。",
          parameters: [public_token_param],
          responses: {
            "200" => json_response("キャンセル済み", ref("Reservation")),
            "404" => error_response("トークンが不正"),
            "409" => error_response("キャンセルできない状態（NOT_CANCELLABLE）")
          }
        }
      },
      "/v1/admin/booking-types" => {
        get: {
          tags: ["admin"], summary: "予約メニュー一覧", operationId: "listBookingTypes",
          security: [{ adminKey: [] }],
          responses: { "200" => json_response("一覧", {
            type: "object",
            properties: { bookingTypes: { type: "array", items: ref("AdminBookingType") } }
          }), "401" => error_response("X-Admin-Key が不正") }
        },
        post: {
          tags: ["admin"], summary: "予約メニューを登録", operationId: "createBookingType",
          security: [{ adminKey: [] }],
          requestBody: {
            required: true,
            content: { "application/json" => { schema: ref("BookingTypeInput") } }
          },
          responses: {
            "201" => json_response("登録済み", ref("AdminBookingType")),
            "401" => error_response("X-Admin-Key が不正"),
            "422" => error_response("入力不正")
          }
        }
      },
      "/v1/admin/booking-types/{id}" => {
        get: {
          tags: ["admin"], summary: "予約メニュー詳細", operationId: "getBookingType",
          security: [{ adminKey: [] }], parameters: [id_param],
          responses: { "200" => json_response("予約メニュー", ref("AdminBookingType")),
                       "404" => error_response("存在しない") }
        },
        patch: {
          tags: ["admin"], summary: "予約メニューを更新", operationId: "updateBookingType",
          description: "送られたキーだけを更新する。allowedOrigins / weeklyAvailability / " \
                       "availabilityOverrides はキーがあれば全置換。",
          security: [{ adminKey: [] }], parameters: [id_param],
          requestBody: {
            required: true,
            content: { "application/json" => { schema: ref("BookingTypeInput") } }
          },
          responses: { "200" => json_response("更新済み", ref("AdminBookingType")),
                       "422" => error_response("入力不正") }
        },
        delete: {
          tags: ["admin"], summary: "予約メニューを削除", operationId: "deleteBookingType",
          description: "予約が紐づいている場合は削除せず 422。受付停止は status: inactive で行う。",
          security: [{ adminKey: [] }], parameters: [id_param],
          responses: { "204" => { description: "削除済み" }, "422" => error_response("予約が存在する") }
        }
      },
      "/v1/admin/reservations" => {
        get: {
          tags: ["admin"], summary: "予約一覧", operationId: "listReservations",
          security: [{ adminKey: [] }],
          parameters: [
            { name: "status", in: "query", required: false,
              schema: { type: "string", enum: Reservation::STATUSES } },
            { name: "slug", in: "query", required: false, schema: { type: "string" } },
            { name: "from", in: "query", required: false, schema: { type: "string", format: "date-time" } },
            { name: "to", in: "query", required: false, schema: { type: "string", format: "date-time" } },
            { name: "limit", in: "query", required: false, schema: { type: "integer", default: 50, maximum: 200 } },
            { name: "offset", in: "query", required: false, schema: { type: "integer", default: 0 } }
          ],
          responses: { "200" => json_response("一覧", {
            type: "object",
            properties: {
              reservations: { type: "array", items: ref("AdminReservation") },
              total: { type: "integer" }, limit: { type: "integer" }, offset: { type: "integer" }
            }
          }) }
        }
      },
      "/v1/admin/reservations/{id}" => {
        get: {
          tags: ["admin"], summary: "予約詳細", operationId: "getAdminReservation",
          security: [{ adminKey: [] }], parameters: [id_param],
          responses: { "200" => json_response("予約", ref("AdminReservation")),
                       "404" => error_response("存在しない") }
        }
      },
      "/v1/admin/reservations/{id}/cancel" => {
        post: {
          tags: ["admin"], summary: "予約をキャンセル", operationId: "adminCancelReservation",
          security: [{ adminKey: [] }], parameters: [id_param],
          responses: { "200" => json_response("キャンセル済み", ref("AdminReservation")),
                       "409" => error_response("キャンセルできない状態") }
        }
      },
      "/v1/admin/reservations/{id}/reschedule" => {
        post: {
          tags: ["admin"], summary: "予約日時を変更", operationId: "rescheduleReservation",
          security: [{ adminKey: [] }], parameters: [id_param],
          requestBody: {
            required: true,
            content: { "application/json" => { schema: {
              type: "object", required: ["startAt"],
              properties: { startAt: { type: "string", format: "date-time", example: "2026-08-05T14:00:00+09:00" } }
            } } }
          },
          responses: {
            "200" => json_response("変更済み", ref("AdminReservation")),
            "409" => error_response("変更先が埋まっている（SLOT_UNAVAILABLE）／変更できない状態"),
            "502" => error_response("Google カレンダーの更新失敗")
          }
        }
      }
    }.merge(google_paths)
  end

  # Google 連携。連携は「認可 URL を発行 → ブラウザで同意 → 設定画面でカレンダーを選ぶ」の順。
  def google_paths
    {
      "/v1/admin/google/oauth/url" => {
        post: {
          tags: ["admin"], summary: "Google 同意画面の URL を発行", operationId: "createGoogleAuthUrl",
          description: "返ってきた authUrl をブラウザで開いて同意する。URL は 10 分で失効する。\n" \
                       "管理 API キーを URL に載せないため、発行と同意を 2 段に分けている。",
          security: [{ adminKey: [] }],
          responses: {
            "200" => json_response("認可 URL", {
              type: "object",
              properties: {
                authUrl: { type: "string", format: "uri" },
                redirectUri: { type: "string", format: "uri",
                               description: "Google Cloud の「承認済みのリダイレクト URI」と一致させる" },
                expiresInSeconds: { type: "integer", example: 600 }
              }
            }),
            "503" => error_response("GOOGLE_OAUTH_CLIENT_ID / SECRET が未設定")
          }
        }
      },
      "/v1/admin/google/oauth/callback" => {
        get: {
          tags: ["admin"], summary: "同意後のコールバック（Google が呼ぶ）",
          operationId: "googleOauthCallback",
          description: "Google からのリダイレクト先。X-Admin-Key は付かないため state の署名で検証する。\n" \
                       "成功すると refresh token を保存し、設定画面へリダイレクトする。",
          parameters: [
            { name: "code", in: "query", schema: { type: "string" } },
            { name: "state", in: "query", schema: { type: "string" } },
            { name: "error", in: "query", schema: { type: "string" },
              description: "同意を拒否した場合などに Google が付ける" }
          ],
          responses: {
            "302" => { description: "連携成功。設定画面へリダイレクトする" },
            "400" => { description: "state が不正・認可コードの交換に失敗（HTML を返す）" }
          }
        }
      },
      "/v1/admin/google/calendars" => {
        get: {
          tags: ["admin"], summary: "連携アカウントのカレンダー一覧", operationId: "listGoogleCalendars",
          description: "設定画面の選択肢と同じデータ。writable が true のものだけ予約の登録先にできる。",
          security: [{ adminKey: [] }],
          responses: {
            "200" => json_response("カレンダー一覧", {
              type: "object",
              properties: {
                connection: ref("GoogleConnection"),
                calendars: { type: "array", items: ref("GoogleCalendar") }
              }
            }),
            "502" => error_response("Google からカレンダーを取得できない（CALENDAR_ERROR）")
          }
        }
      },
      "/v1/admin/google/setup" => {
        get: {
          tags: ["admin"], summary: "カレンダー設定画面（HTML）", operationId: "googleSetupPage",
          description: "同意直後に発行される短期セッション Cookie（30 分）か X-Admin-Key で開ける。",
          security: [{ adminKey: [] }],
          responses: { "200" => { description: "設定画面の HTML" },
                       "401" => { description: "セッション切れ・認証なし" } }
        },
        post: {
          tags: ["admin"], summary: "カレンダーの選択を保存", operationId: "saveGoogleCalendarSelection",
          description: "フォーム送信（application/x-www-form-urlencoded）。Cookie 認証のときは " \
                       "csrfToken が必須。X-Admin-Key のときは不要。",
          security: [{ adminKey: [] }],
          responses: { "200" => { description: "保存後の設定画面 HTML" },
                       "403" => { description: "CSRF トークンが不正" },
                       "422" => { description: "存在しない予約メニューを指定した" } }
        }
      },
      "/v1/admin/google/disconnect" => {
        post: {
          tags: ["admin"], summary: "Google 連携を解除", operationId: "disconnectGoogle",
          description: "保存済みの refresh token を削除する。以後、空き取得と予約登録は 502 になる。",
          security: [{ adminKey: [] }],
          responses: { "200" => { description: "解除後の設定画面 HTML" } }
        }
      }
    }
  end

  def components
    {
      securitySchemes: {
        adminKey: { type: "apiKey", in: "header", name: "X-Admin-Key",
                    description: "管理 API の共有シークレット。値はドキュメントに記載しない。" }
      },
      schemas: {
        "Error" => {
          type: "object", required: %w[code message],
          properties: {
            code: { type: "string", example: "SLOT_UNAVAILABLE" },
            message: { type: "string", example: "選択された時間は利用できなくなりました。" },
            details: { type: "array", items: { type: "string" } }
          }
        },
        "HealthStatus" => {
          type: "object",
          properties: { status: { type: "string", example: "ok" }, version: { type: "string" } }
        },
        "ReadyStatus" => {
          type: "object",
          properties: { status: { type: "string", example: "ready" }, database: { type: "string", example: "ok" } }
        },
        "PublicBookingType" => {
          type: "object",
          properties: {
            slug: { type: "string", example: "genba-tsunagu-consultation" },
            name: { type: "string", example: "無料相談" },
            description: { type: %w[string null] },
            durationMinutes: { type: "integer", example: 60 },
            timeZone: { type: "string", example: "Asia/Tokyo" },
            minimumNoticeMinutes: { type: "integer", example: 1440 },
            bookingWindowDays: { type: "integer", example: 30 }
          }
        },
        "AdminBookingType" => {
          allOf: [
            ref("PublicBookingType"),
            {
              type: "object",
              properties: {
                id: { type: "integer" },
                status: { type: "string", enum: BookingType::STATUSES },
                bufferBeforeMinutes: { type: "integer" },
                bufferAfterMinutes: { type: "integer" },
                googleBookingCalendarId: { type: %w[string null] },
                googleBusyCalendarIds: { type: "array", items: { type: "string" } },
                allowedOrigins: { type: "array", items: { type: "string" } },
                weeklyAvailability: { type: "array", items: ref("WeeklyAvailabilityEntry") },
                availabilityOverrides: { type: "array", items: ref("AvailabilityOverrideEntry") },
                createdAt: { type: "string", format: "date-time" },
                updatedAt: { type: "string", format: "date-time" }
              }
            }
          ]
        },
        "WeeklyAvailabilityEntry" => {
          type: "object", required: %w[dayOfWeek startTime endTime],
          properties: {
            dayOfWeek: { type: "integer", minimum: 0, maximum: 6, description: "0=日曜 ... 6=土曜" },
            startTime: { type: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", example: "10:00" },
            endTime: { type: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", example: "18:00" }
          }
        },
        "AvailabilityOverrideEntry" => {
          type: "object", required: %w[date isAvailable],
          description: "isAvailable=false で休業。true のときは startTime / endTime が必須で、その日だけ受付時間を差し替える。",
          properties: {
            date: { type: "string", format: "date", example: "2026-08-13" },
            isAvailable: { type: "boolean", example: false },
            startTime: { type: %w[string null], example: "13:00" },
            endTime: { type: %w[string null], example: "17:00" }
          }
        },
        "GoogleConnection" => {
          type: "object",
          description: "Google 連携の状態。refresh token は暗号文も含めて返さない。",
          properties: {
            connected: { type: "boolean" },
            googleAccountEmail: { type: "string", example: "you@example.com" },
            scopes: { type: "array", items: { type: "string" } },
            missingScopes: {
              type: "array", items: { type: "string" },
              description: "要求したのに同意されなかったスコープ。空でなければ連携をやり直す。"
            },
            connectedAt: { type: "string", format: "date-time" }
          }
        },
        "GoogleCalendar" => {
          type: "object",
          properties: {
            id: { type: "string", example: "you@example.com" },
            summary: { type: "string", example: "メイン" },
            primary: { type: "boolean" },
            accessRole: { type: "string", example: "owner" },
            writable: { type: "boolean", description: "true のものだけ予約の登録先にできる" }
          }
        },
        "BookingTypeInput" => {
          type: "object",
          properties: {
            name: { type: "string", example: "無料相談" },
            slug: { type: "string", pattern: "^[a-z0-9]+(-[a-z0-9]+)*$", example: "genba-tsunagu-consultation" },
            description: { type: %w[string null] },
            durationMinutes: { type: "integer", example: 60 },
            timeZone: { type: "string", example: "Asia/Tokyo" },
            minimumNoticeMinutes: { type: "integer", example: 1440 },
            bookingWindowDays: { type: "integer", example: 30 },
            bufferBeforeMinutes: { type: "integer", example: 0 },
            bufferAfterMinutes: { type: "integer", example: 0 },
            googleBookingCalendarId: { type: %w[string null],
                                       description: "未指定なら GOOGLE_BOOKING_CALENDAR_ID を使う" },
            googleBusyCalendarIds: {
              type: "array", items: { type: "string" },
              description: "空き判定に使うカレンダー。空配列なら GOOGLE_BUSY_CALENDAR_IDS を使う。" \
                           "設定画面（/v1/admin/google/setup）から選ぶこともできる。"
            },
            status: { type: "string", enum: BookingType::STATUSES },
            allowedOrigins: { type: "array", items: { type: "string", example: "https://genba-tsunagu.jp" } },
            weeklyAvailability: { type: "array", items: ref("WeeklyAvailabilityEntry") },
            availabilityOverrides: { type: "array", items: ref("AvailabilityOverrideEntry") }
          }
        },
        "Availability" => {
          type: "object",
          properties: {
            timeZone: { type: "string", example: "Asia/Tokyo" },
            durationMinutes: { type: "integer", example: 60 },
            days: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  date: { type: "string", format: "date", example: "2026-08-03" },
                  slots: { type: "array", items: ref("Slot") }
                }
              }
            }
          }
        },
        "Slot" => {
          type: "object",
          properties: {
            startAt: { type: "string", format: "date-time", example: "2026-08-03T10:00:00+09:00" },
            endAt: { type: "string", format: "date-time", example: "2026-08-03T11:00:00+09:00" }
          }
        },
        "CreateReservationRequest" => {
          type: "object", required: %w[startAt guest],
          properties: {
            startAt: { type: "string", format: "date-time", example: "2026-08-03T10:00:00+09:00",
                       description: "空き枠 API が返した startAt をそのまま送る" },
            guest: {
              type: "object", required: %w[name email],
              properties: {
                name: { type: "string", example: "山田太郎" },
                email: { type: "string", format: "email", example: "taro@example.com" },
                company: { type: %w[string null], example: "株式会社サンプル" },
                phone: { type: %w[string null], example: "090-0000-0000" }
              }
            },
            answers: {
              type: "object", additionalProperties: { type: "string" },
              description: "予約メニューごとの自由項目（最大 30 件・各 2000 文字）",
              example: { "相談内容" => "日報業務を自動化したい" }
            },
            turnstileToken: { type: "string", description: "Cloudflare Turnstile のトークン" }
          }
        },
        "Reservation" => {
          type: "object",
          properties: {
            reservationId: { type: "string", example: "res_Ab3xY..." },
            status: { type: "string", enum: Reservation::STATUSES },
            startAt: { type: "string", format: "date-time" },
            endAt: { type: "string", format: "date-time" },
            bookingType: {
              type: "object",
              properties: {
                slug: { type: "string" }, name: { type: "string" },
                durationMinutes: { type: "integer" }, timeZone: { type: "string" }
              }
            },
            guest: {
              type: "object",
              properties: {
                name: { type: "string" }, email: { type: "string" },
                company: { type: %w[string null] }, phone: { type: %w[string null] }
              }
            },
            answers: { type: "object", additionalProperties: { type: "string" } },
            cancelledAt: { type: %w[string null], format: "date-time" }
          }
        },
        "ReservationWithCancelUrl" => {
          allOf: [
            ref("Reservation"),
            {
              type: "object",
              properties: {
                cancelUrl: {
                  type: "string",
                  description: "キャンセル用 URL。トークンを含むため、この応答と確認メールにのみ現れる。"
                }
              }
            }
          ]
        },
        "AdminReservation" => {
          allOf: [
            ref("Reservation"),
            {
              type: "object",
              properties: {
                id: { type: "integer" },
                bookingTypeId: { type: "integer" },
                googleEventId: { type: %w[string null] },
                expiresAt: { type: %w[string null], format: "date-time" },
                createdAt: { type: "string", format: "date-time" },
                updatedAt: { type: "string", format: "date-time" }
              }
            }
          ]
        }
      }
    }
  end

  def ref(name)
    { "$ref" => "#/components/schemas/#{name}" }
  end

  def json_response(description, schema)
    { description: description, content: { "application/json" => { schema: schema } } }
  end

  def error_response(description)
    json_response(description, ref("Error"))
  end

  def slug_param
    { name: "slug", in: "path", required: true, schema: { type: "string" },
      example: "genba-tsunagu-consultation" }
  end

  def id_param
    { name: "id", in: "path", required: true, schema: { type: "integer" } }
  end

  def public_token_param
    { name: "publicToken", in: "path", required: true, schema: { type: "string" },
      description: "確認メールのキャンセル URL に含まれるトークン" }
  end

  def idempotency_key_param
    { name: "Idempotency-Key", in: "header", required: true,
      schema: { type: "string", format: "uuid" },
      description: "再送で二重予約にならないようにするためのキー。予約ごとに一意な値を生成する。" }
  end
end
