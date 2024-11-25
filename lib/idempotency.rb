# frozen_string_literal: true

require 'dry-configurable'
require 'json'
require_relative 'idempotency/cache'
require_relative 'idempotency/rails'

module Idempotency
  extend Dry::Configurable

  setting :redis_pool
  setting :default_lock_expiry
  setting :logger

  setting :response_body do
    setting :concurrent_error, default: {
      errors: [{ message: 'Request conflicts with another likely concurrent request.' }]
    }.to_json
  end

  def self.cache
    @cache ||= Cache.new(config:)
  end
end
