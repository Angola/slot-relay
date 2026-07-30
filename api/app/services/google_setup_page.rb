# frozen_string_literal: true

# Google 連携の設定画面の HTML。
#
# API モード（`config.api_only = true`）でテンプレート描画を有効にしていないため、
# DocsController が Swagger UI の HTML を組み立てているのと同じやり方で文字列を作る。
# 管理者 1 人が使う設定画面なので、CSS は最小限のインラインで済ませる。
class GoogleSetupPage
  include ERB::Util

  SETUP_PATH = "/v1/admin/google/setup"
  LOGIN_PATH = "/v1/admin/google/login"
  CONNECT_PATH = "/v1/admin/google/connect"
  DISCONNECT_PATH = "/v1/admin/google/disconnect"

  def initialize(connection:, calendars:, booking_types:, csrf_token:, notice: nil, error: nil)
    @connection = connection
    @calendars = calendars
    @booking_types = booking_types
    @csrf_token = csrf_token
    @notice = notice
    @error = error
  end

  def render
    layout(body)
  end

  class << self
    include ERB::Util

    def error_html(message)
      new(connection: nil, calendars: [], booking_types: [], csrf_token: nil)
        .send(:layout, <<~HTML)
          <div class="card error">
            <h2>Google 連携に失敗しました</h2>
            <p>#{html_escape(message)}</p>
            <p class="muted">最初からやり直すには、管理 API の
              <code>POST /v1/admin/google/oauth/url</code> で認可 URL を発行し直してください。</p>
          </div>
        HTML
    end

    # ログインフォーム。ブラウザは任意のヘッダを付けられないので、
    # 管理キーは POST のボディで受け取る（URL・履歴・Referer に残さない）。
    def login_html(error: nil)
      message = error.present? ? %(<p class="warn">#{html_escape(error)}</p>) : ""

      new(connection: nil, calendars: [], booking_types: [], csrf_token: nil)
        .send(:layout, <<~HTML)
          <div class="card">
            <h2>管理 API キーでログイン</h2>
            <p class="muted">Google 連携の設定画面を開きます。セッションは 30 分で切れます。</p>
            #{message}
            <form method="post" action="#{LOGIN_PATH}">
              <label class="field">
                <span>管理 API キー（<code>ADMIN_API_KEY</code>）</span>
                <input type="password" name="adminKey" autocomplete="off" autofocus required>
              </label>
              <button type="submit" class="primary">開く</button>
            </form>
          </div>
        HTML
    end
  end

  private

  attr_reader :connection, :calendars, :booking_types, :csrf_token, :notice, :error

  def body
    [
      messages,
      connection_card,
      connected? ? booking_types_form : nil
    ].compact.join("\n")
  end

  def connected?
    connection.present? && connection.usable?
  end

  def messages
    parts = []
    parts << %(<div class="card notice"><p>#{html_escape(notice)}</p></div>) if notice.present?
    parts << %(<div class="card error"><p>#{html_escape(error)}</p></div>) if error.present?
    parts.join("\n")
  end

  def connection_card
    return disconnected_card unless connected?

    <<~HTML
      <div class="card">
        <h2>Google 連携</h2>
        <dl>
          <dt>アカウント</dt><dd><strong>#{html_escape(connection.google_account_email)}</strong></dd>
          <dt>連携日時</dt><dd>#{html_escape(connection.connected_at.in_time_zone("Asia/Tokyo").strftime("%Y/%m/%d %H:%M"))}</dd>
        </dl>
        #{missing_scopes_warning}
        <div class="row">
          <form method="post" action="#{CONNECT_PATH}">
            #{csrf_field}
            <button type="submit">連携をやり直す</button>
          </form>
          <form method="post" action="#{DISCONNECT_PATH}"
                onsubmit="return confirm('連携を解除します。空き取得と予定作成ができなくなります。よろしいですか？');">
            #{csrf_field}
            <button type="submit" class="danger">連携を解除する</button>
          </form>
        </div>
      </div>
    HTML
  end

  def disconnected_card
    <<~HTML
      <div class="card">
        <h2>Google 未連携</h2>
        <p>まだ Google アカウントが連携されていません。空き時間の取得と予定の作成ができません。</p>
        <form method="post" action="#{CONNECT_PATH}">
          #{csrf_field}
          <button type="submit" class="primary">Google と連携する</button>
        </form>
        <p class="muted">ボタンを押すと Google の同意画面に移ります。同意後、この画面に戻って
          使うカレンダーを選べます。API から行う場合は
          <code>POST /v1/admin/google/oauth/url</code>（Swagger UI は <a href="/docs">/docs</a>）。</p>
      </div>
    HTML
  end

  def missing_scopes_warning
    missing = connection.missing_scopes
    return "" if missing.empty?

    <<~HTML
      <p class="warn">同意されていない権限があります。カレンダーの取得や予定の作成に失敗する場合は、
        連携をやり直してすべての権限を許可してください。<br>
        <code>#{html_escape(missing.join(", "))}</code></p>
    HTML
  end

  def booking_types_form
    return %(<div class="card"><p class="muted">予約メニューがまだありません。</p></div>) if booking_types.empty?

    <<~HTML
      <form method="post" action="#{SETUP_PATH}">
        #{csrf_field}
        #{booking_types.map { |bt| booking_type_card(bt) }.join("\n")}
        <div class="card actions">
          <button type="submit" class="primary">保存する</button>
        </div>
      </form>
    HTML
  end

  def booking_type_card(booking_type)
    <<~HTML
      <div class="card">
        <h2>#{html_escape(booking_type.name)}
          <span class="muted">#{html_escape(booking_type.slug)}</span></h2>

        <h3>予約の登録先カレンダー</h3>
        <p class="muted">確定した予約の予定を作るカレンダー。書き込み権限のあるものだけ選べます。</p>
        #{booking_calendar_radios(booking_type)}

        <h3>空き判定に使うカレンダー</h3>
        <p class="muted">ここで選んだカレンダーに予定がある時間は、空き枠から外します。
          登録先カレンダー自身は選ばなくても必ず対象になります。</p>
        #{busy_calendar_checkboxes(booking_type)}
      </div>
    HTML
  end

  def booking_calendar_radios(booking_type)
    writable = calendars.select(&:writable?)
    return %(<p class="warn">書き込みできるカレンダーがありません。</p>) if writable.empty?

    field = "booking_types[#{booking_type.id}][booking_calendar_id]"
    current = booking_type.google_booking_calendar_id

    options = writable.map do |entry|
      checked = entry.id == current ? " checked" : ""
      <<~HTML
        <label class="option">
          <input type="radio" name="#{field}" value="#{html_escape(entry.id)}"#{checked}>
          <span>#{html_escape(entry.summary)}#{primary_badge(entry)}</span>
          <code>#{html_escape(entry.id)}</code>
        </label>
      HTML
    end

    # 未選択（環境変数の既定値にフォールバック）も選べるようにする
    options.unshift(<<~HTML)
      <label class="option">
        <input type="radio" name="#{field}" value=""#{current.blank? ? " checked" : ""}>
        <span class="muted">指定しない（環境変数 GOOGLE_BOOKING_CALENDAR_ID の値を使う）</span>
      </label>
    HTML

    options.join("\n")
  end

  def busy_calendar_checkboxes(booking_type)
    return %(<p class="warn">カレンダーを取得できませんでした。</p>) if calendars.empty?

    field = "booking_types[#{booking_type.id}][busy_calendar_ids][]"
    selected = Array(booking_type.google_busy_calendar_ids)

    # 何も選ばれずに POST されたとき配列を空にできるよう、空値を必ず 1 つ送る
    hidden = %(<input type="hidden" name="#{field}" value="">)

    boxes = calendars.map do |entry|
      checked = selected.include?(entry.id) ? " checked" : ""
      <<~HTML
        <label class="option">
          <input type="checkbox" name="#{field}" value="#{html_escape(entry.id)}"#{checked}>
          <span>#{html_escape(entry.summary)}#{primary_badge(entry)}</span>
          <code>#{html_escape(entry.id)}</code>
        </label>
      HTML
    end

    ([hidden] + boxes).join("\n")
  end

  def primary_badge(entry)
    entry.primary ? %( <span class="badge">メイン</span>) : ""
  end

  def csrf_field
    return "" if csrf_token.blank?

    %(<input type="hidden" name="csrfToken" value="#{html_escape(csrf_token)}">)
  end

  def layout(inner)
    <<~HTML
      <!doctype html>
      <html lang="ja">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="robots" content="noindex, nofollow">
          <!-- 設定画面の URL を外部サイトへ漏らさない -->
          <meta name="referrer" content="no-referrer">
          <title>Google 連携設定 — slot-relay</title>
          <style>#{styles}</style>
        </head>
        <body>
          <main>
            <h1>Google 連携設定</h1>
            #{inner}
          </main>
        </body>
      </html>
    HTML
  end

  def styles
    <<~CSS
      :root { color-scheme: light dark; }
      * { box-sizing: border-box; }
      body {
        margin: 0; padding: 24px 16px;
        font-family: system-ui, -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif;
        line-height: 1.7; background: #f6f7f9; color: #1a1d21;
      }
      main { max-width: 720px; margin: 0 auto; }
      h1 { font-size: 20px; margin: 0 0 16px; }
      h2 { font-size: 16px; margin: 0 0 4px; }
      h3 { font-size: 14px; margin: 20px 0 4px; }
      .card {
        background: #fff; border: 1px solid #e3e6ea; border-radius: 10px;
        padding: 16px 20px; margin-bottom: 16px;
      }
      .card.notice { border-color: #7cc4a4; background: #f2fbf6; }
      .card.error  { border-color: #e0a1a1; background: #fdf4f4; }
      .card.actions { position: sticky; bottom: 16px; text-align: right; }
      dl { display: grid; grid-template-columns: 100px 1fr; gap: 4px 12px; margin: 8px 0 16px; }
      dt { color: #6b7280; font-size: 13px; }
      dd { margin: 0; }
      .muted { color: #6b7280; font-size: 13px; }
      .warn { color: #9a3412; font-size: 13px; }
      .badge {
        display: inline-block; margin-left: 6px; padding: 0 6px;
        border-radius: 999px; background: #eef2ff; color: #3730a3; font-size: 11px;
      }
      .option {
        display: grid; grid-template-columns: auto 1fr; gap: 4px 8px;
        align-items: center; padding: 8px 10px; border-radius: 8px; cursor: pointer;
      }
      .option:hover { background: #f3f4f6; }
      .option code {
        grid-column: 2; font-size: 11px; color: #6b7280; word-break: break-all;
      }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
      button {
        font: inherit; padding: 8px 20px; border-radius: 8px;
        border: 1px solid #d1d5db; background: #fff; cursor: pointer;
      }
      button.primary { background: #2563eb; color: #fff; border-color: #2563eb; }
      button.danger { background: #fff; color: #b91c1c; border-color: #e0a1a1; }
      .row { display: flex; gap: 8px; flex-wrap: wrap; }
      .field { display: block; margin: 12px 0; }
      .field span { display: block; font-size: 13px; margin-bottom: 4px; }
      .field input {
        font: inherit; width: 100%; padding: 8px 10px;
        border: 1px solid #d1d5db; border-radius: 8px; background: #fff; color: inherit;
      }
      a { color: #2563eb; }
      @media (prefers-color-scheme: dark) {
        body { background: #16181d; color: #e5e7eb; }
        .card { background: #1e2126; border-color: #2f343b; }
        .card.notice { background: #14251c; border-color: #2f6b4c; }
        .card.error  { background: #2a1a1a; border-color: #7f3a3a; }
        .option:hover { background: #262a31; }
        .muted, dt, .option code { color: #9ca3af; }
        button { background: #262a31; color: #e5e7eb; border-color: #3f4550; }
        button.danger { background: #1e2126; color: #f87171; border-color: #7f3a3a; }
        .field input { background: #262a31; border-color: #3f4550; }
      }
    CSS
  end
end
