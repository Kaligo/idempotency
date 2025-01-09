# frozen_string_literal: true

RSpec.describe Idempotency::Instrumentation::StatsdListener do
  let(:statsd_client) { double('statsd_client') }
  let(:namespace) { 'test_app' }
  let(:listener) { described_class.new(statsd_client, namespace) }
  let(:request) do
    double(
      'Request',
      request_method: 'POST',
      path: '/orders/123'
    )
  end
  let(:event_payload) do
    {
      request: request,
      action: 'POST:/orders/create',
      duration: 0.1
    }
  end
  let(:notifier) do
    Dry::Monitor::Notifications.new(:test).tap do |n|
      Idempotency::Events::ALL_EVENTS.each { |event| n.register_event(event) }
    end
  end

  before do
    allow(Idempotency).to receive(:notifier).and_return(notifier)
    listener.setup_subscriptions
  end

  context 'when cache hit event is triggered' do
    it 'sends correct metrics' do
      expect(statsd_client).to receive(:increment).with(
        'idempotency_cache_hit_count',
        tags: ['action:POST:/orders/create', 'namespace:test_app']
      )
      expect(statsd_client).to receive(:histogram).with(
        'idempotency_cache_duration_seconds',
        0.1,
        tags: [
          'action:POST:/orders/create',
          'namespace:test_app',
          'metric:idempotency_cache_hit_count'
        ]
      )

      Idempotency.notifier.instrument(Idempotency::Events::CACHE_HIT, event_payload)
    end
  end

  context 'when cache miss event is triggered' do
    it 'sends correct metrics' do
      expect(statsd_client).to receive(:increment).with(
        'idempotency_cache_miss_count',
        tags: ['action:POST:/orders/create', 'namespace:test_app']
      )
      expect(statsd_client).to receive(:histogram).with(
        'idempotency_cache_duration_seconds',
        0.1,
        tags: [
          'action:POST:/orders/create',
          'namespace:test_app',
          'metric:idempotency_cache_miss_count'
        ]
      )

      Idempotency.notifier.instrument(Idempotency::Events::CACHE_MISS, event_payload)
    end
  end

  context 'when lock conflict event is triggered' do
    it 'sends correct metrics' do
      expect(statsd_client).to receive(:increment).with(
        'idempotency_lock_conflict_count',
        tags: ['action:POST:/orders/create', 'namespace:test_app']
      )
      expect(statsd_client).to receive(:histogram).with(
        'idempotency_cache_duration_seconds',
        0.1,
        tags: [
          'action:POST:/orders/create',
          'namespace:test_app',
          'metric:idempotency_lock_conflict_count'
        ]
      )

      Idempotency.notifier.instrument(Idempotency::Events::LOCK_CONFLICT, event_payload)
    end
  end

  context 'when action is not provided' do
    let(:event_payload) do
      {
        request: request,
        duration: 0.1
      }
    end

    it 'uses request method and path as action' do
      expect(statsd_client).to receive(:increment).with(
        'idempotency_cache_hit_count',
        tags: ['action:POST:/orders/123', 'namespace:test_app']
      )
      expect(statsd_client).to receive(:histogram).with(
        'idempotency_cache_duration_seconds',
        0.1,
        tags: [
          'action:POST:/orders/123',
          'namespace:test_app',
          'metric:idempotency_cache_hit_count'
        ]
      )

      Idempotency.notifier.instrument(Idempotency::Events::CACHE_HIT, event_payload)
    end
  end

  context 'when namespace is not provided' do
    let(:listener) { described_class.new(statsd_client) }

    it 'does not include namespace tag' do
      expect(statsd_client).to receive(:increment).with(
        'idempotency_cache_hit_count',
        tags: ['action:POST:/orders/create']
      )
      expect(statsd_client).to receive(:histogram).with(
        'idempotency_cache_duration_seconds',
        0.1,
        tags: [
          'action:POST:/orders/create',
          'metric:idempotency_cache_hit_count'
        ]
      )

      Idempotency.notifier.instrument(Idempotency::Events::CACHE_HIT, event_payload)
    end
  end
end
