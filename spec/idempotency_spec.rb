# frozen_string_literal: true

RSpec.describe Idempotency do
  let(:mock_redis) { MockRedis.new }
  let(:redis_pool) { ConnectionPool.new { mock_redis } }
  it 'has a version number' do
    expect(Idempotency::VERSION).not_to be nil
  end

  after { Idempotency.reset_config }

  describe '#use_cache' do
    subject { described_class.new(cache:).use_cache(request, request_ids, lock_duration:, &controller_action) }

    let(:controller_action) do
      lambda do
        response
      end
    end
    let(:request_ids) { ['tenant_id'] }
    let(:request) do
      double(
        'Request',
        request_method: request_method,
        path: '/int/orders/a960e817-3b3c-487c-8db4-7a1d065f52b7',
        env: request_headers
      )
    end
    let(:request_method) { 'POST' }
    let(:request_headers) { { 'HTTP_IDEMPOTENCY_KEY' => idempotency_key } }
    let(:lock_duration) { 30 }

    let(:idempotency_key) { SecureRandom.uuid }
    let(:fingerprint) do
      d = Digest::SHA256.new
      d << idempotency_key
      d << request.path
      d << request.request_method
      d << request_ids.first
      Base64.strict_encode64(d.digest)
    end
    let(:cache_key) { "idempotency:cached_response:#{fingerprint}" }
    let(:cache) { Idempotency::Cache.new(config: Idempotency.config) }

    context 'when request is cached' do
      let(:cached_headers) { { 'key' => 'value' } }
      let(:cached_status) { 201 }
      let(:cached_body) { { offer_id: SecureRandom.uuid }.to_json }
      let(:response) { nil }
      let(:expected_response) do
        [
          cached_status,
          cached_headers.merge('Idempotency-Key' => idempotency_key),
          cached_body
        ]
      end

      before do
        cache.set(fingerprint, cached_status, cached_headers, cached_body)
      end

      it { is_expected.to eq(expected_response) }
    end

    context 'when request is not cached' do
      context 'when request is not cachable' do
        let(:response) { [500, {}, { error: 'some_error' }.to_json] }

        before do
          expect(cache)
            .to receive(:release_lock)
            .with(fingerprint, be_a(String))
        end

        it 'return response and does not cache response' do
          expect { is_expected.to eq(response) }.not_to(change { cache.get(fingerprint) })
        end
      end

      context 'when request is cachable' do
        let(:response) { [400, {}, { error: 'some_error' }.to_json] }

        before do
          expect(cache)
            .to receive(:release_lock)
            .with(fingerprint, be_a(String))
        end

        it 'return response and caches response' do
          expect { is_expected.to eq(response) }
            .to change { cache.get(fingerprint) }
            .from(nil).to([400, {}, { error: 'some_error' }.to_json])
        end
      end

      context 'when there is concurrent request' do
        let(:response) { nil }
        let(:expected_response) { [409, {}, Idempotency.config.response_body.concurrent_error] }

        it 'returns 409 error and does not cache request' do
          expect { is_expected.to eq(expected_response) }.not_to(change { cache.get(fingerprint) })
        end
      end
    end
  end

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
