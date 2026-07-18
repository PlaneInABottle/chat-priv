# frozen_string_literal: true

require 'digest'

module AiAgents::CatalogImageIdentity
  def self.for(url)
    Digest::SHA256.hexdigest(url.to_s)
  end
end
