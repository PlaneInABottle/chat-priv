# frozen_string_literal: true

class AccountVoiceAiSettingsField < Administrate::Field::Base
  def html_name
    "#{resource.class.name.underscore}[#{attribute}]"
  end

  def to_s
    key = resource.voice_ai_enabled? ? 'enabled' : 'disabled'
    I18n.t("super_admin.account_voice_ai_settings.#{key}")
  end
end
