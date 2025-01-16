# frozen_string_literal: true

RSpec.describe Idempotency do
  let(:mock_redis) { MockRedis.new }
  let(:redis_pool) { ConnectionPool.new { mock_redis } }
  it 'has a version number' do
    expect(Idempotency::VERSION).not_to be nil
  end
  let(:notifier) { double(Dry::Monitor::Notifications) }

  before do
    allow(Idempotency).to receive(:notifier).and_return(notifier)
  end

  after { Idempotency.reset_config }

  describe '#use_cache' do
    subject { described_class.new(cache:).use_cache(request, request_ids, lock_duration:, action:, &controller_action) }

    let(:statsd_client) { double('statsd_client') }
    let(:controller_action) do
      lambda do
        response
      end
    end
    let(:action) { 'POST:/int/orders/order_id' }
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

      it 'returns cached response and logs cache hit event' do
        expect(notifier).to receive(:instrument).with(
          Idempotency::Events::CACHE_HIT,
          request: request,
          action: action,
          duration: be_kind_of(Numeric)
        )

        is_expected.to eq(expected_response)
      end
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
          expect(notifier).to receive(:instrument).with(
            Idempotency::Events::CACHE_MISS,
            request: request,
            action: action,
            duration: be_kind_of(Numeric)
          )

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

        it 'returns response, caches it, and logs cache miss metric' do
          expect(notifier).to receive(:instrument).with(
            Idempotency::Events::CACHE_MISS,
            request: request,
            action: action,
            duration: be_kind_of(Numeric)
          )

          expect { is_expected.to eq(response) }
            .to change { cache.get(fingerprint) }
            .from(nil).to([400, {}, { error: 'some_error' }.to_json])
        end
      end

      context 'when there is concurrent request' do
        let(:response) { nil }
        let(:expected_response) { [409, {}, Idempotency.config.response_body.concurrent_error] }

        it 'returns 409 error and does not cache request' do
          expect(notifier).to receive(:instrument).with(
            Idempotency::Events::LOCK_CONFLICT,
            request: request,
            action: action,
            duration: be_kind_of(Numeric)
          )

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

  describe '#configure' do
    let(:statsd_client) { double('statsd_client') }
    let(:custom_listener) { double('custom_listener', setup_subscriptions: true) }

    before do
      described_class.config.metrics.statsd_client = nil
      described_class.config.instrumentation_listeners = []
    end

    it 'sets up StatsdListener when statsd_client is configured' do
      expect(Idempotency::Instrumentation::StatsdListener).to receive(:new)
        .with(statsd_client, 'test_namespace')
        .and_return(custom_listener)

      described_class.configure do |config|
        config.metrics.statsd_client = statsd_client
        config.metrics.namespace = 'test_namespace'
      end

      expect(described_class.config.instrumentation_listeners).to include(custom_listener)
    end

    it 'calls setup_subscriptions on all listeners' do
      described_class.config.instrumentation_listeners = [custom_listener]
      expect(custom_listener).to receive(:setup_subscriptions)

      described_class.configure
    end

    it 'does not add StatsdListener when statsd_client is not configured' do
      described_class.configure do |config|
        config.metrics.namespace = 'test_namespace'
      end

      expect(described_class.config.instrumentation_listeners).to be_empty
    end
  end
end
