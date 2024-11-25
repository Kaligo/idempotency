# frozen_string_literal: true

RSpec.describe Idempotency do
  let(:redis_pool) { ConnectionPool.new { MockRedis.new } }
  it 'has a version number' do
    expect(Idempotency::VERSION).not_to be nil
  end

  after { Idempotency.reset_config }

  it 'allows configuration' do
    Idempotency.configure do |config|
      config.redis_pool = redis_pool
      config.default_lock_expiry = 60

      config.response_body.concurrent_error = {
        errors: [{ code: 'GH0004', message: 'Some message' }]
      }
    end

    config = Idempotency.config
    expect(config.redis_pool).to eq(redis_pool)
    expect(config.default_lock_expiry).to eq(60)
    expect(config.response_body.concurrent_error).to eq({ errors: [{ code: 'GH0004', message: 'Some message' }] })
  end
end
