class ApiController < ApplicationController
  skip_before_action :set_current_user, only: [:index]

  def index
    render json: { status: services_healthy? ? 'ok' : 'failing' }
  end

  private

  def services_healthy?
    redis_status == 'ok' && postgres_status == 'ok'
  end

  def redis_status
    redis = Redis.new(Redis::Config.app)
    return 'ok' if redis.ping
  rescue Redis::CannotConnectError
    'failing'
  end

  def postgres_status
    ActiveRecord::Base.connection.active? ? 'ok' : 'failing'
  rescue ActiveRecord::ConnectionNotEstablished
    'failing'
  end
end
