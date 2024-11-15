# frozen_string_literal: true

require 'idempotency'
require 'pry-byebug'
require 'mock_redis'
require 'dry/configurable/test_interface'

Idempotency.configure do |config|
  config.redis_pool = ConnectionPool.new { MockRedis.new }
  config.logger = Logger.new(nil)
end

module Idempotency
  enable_test_interface

  def self.reset_config
    super
    config.redis_pool = ConnectionPool.new { MockRedis.new }
    config.logger = Logger.new(nil)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
end
