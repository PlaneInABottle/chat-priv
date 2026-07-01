class SuperAdmin::VoiceProviderConnectionsController < SuperAdmin::ApplicationController
  def resource_params
    normalize_settings(super)
  end

  private

  def normalize_settings(permitted_params)
    return permitted_params unless permitted_params[:settings].is_a?(String)

    permitted_params[:settings] = permitted_params[:settings].blank? ? {} : JSON.parse(permitted_params[:settings])
    permitted_params
  rescue JSON::ParserError
    permitted_params[:settings] = {}
    permitted_params
  end
end
