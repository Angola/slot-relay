# frozen_string_literal: true

# SMTP 障害を再現する ActionMailer の配信方式。
# 「メール送信に失敗しても予約は成立させる」を実際の配信経路で検証するために使う。
class FailingDeliveryMethod
  def initialize(**_settings); end

  def deliver!(_mail)
    raise Net::SMTPFatalError, "smtp down (test)"
  end
end

ActionMailer::Base.add_delivery_method :failing, FailingDeliveryMethod

module FailingMailHelper
  # ブロックの中だけメール送信が必ず失敗する状態にする。
  def with_failing_mail
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :failing
    yield
  ensure
    ActionMailer::Base.delivery_method = original
  end
end
