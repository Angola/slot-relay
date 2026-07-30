# frozen_string_literal: true

# Google 連携状態の JSON 表現。キーは camelCase（他の管理 API に合わせる）。
#
# refresh token は暗号文も含めて**一切返さない**。
module GoogleConnectionSerializer
  module_function

  def payload(connection)
    return { connected: false } if connection.blank?

    {
      connected: connection.usable?,
      googleAccountEmail: connection.google_account_email,
      scopes: connection.scopes,
      missingScopes: connection.missing_scopes,
      connectedAt: connection.connected_at.iso8601
    }
  end

  def calendar_payload(entry)
    {
      id: entry.id,
      summary: entry.summary,
      primary: entry.primary,
      accessRole: entry.access_role,
      writable: entry.writable?
    }
  end
end
