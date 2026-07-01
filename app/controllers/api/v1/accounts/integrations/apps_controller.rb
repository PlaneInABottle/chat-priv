class Api::V1::Accounts::Integrations::AppsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, except: [:index, :show]
  before_action :fetch_apps, only: [:index]
  before_action :fetch_app, only: [:show]

  def index; end

  def show; end

  private

  def fetch_apps
    @apps = Integrations::App.all.select { |app| app.active?(Current.account) }
  end

  def fetch_app
    @app = Integrations::App.find(id: params[:id])
    return if @app&.active?(Current.account)

    render_not_found_error('Resource could not be found')
  end
end
