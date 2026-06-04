# frozen_string_literal: true

if Rails.env.development? && ENV['DISABLE_MINI_PROFILER'].blank?
  require 'rack/files'
  Rack.const_set(:File, Rack::Files) unless Rack.const_defined?(:File, false)
  require 'rack-mini-profiler'

  # initialization is skipped so trigger it
  Rack::MiniProfilerRails.initialize!(Rails.application)
end
