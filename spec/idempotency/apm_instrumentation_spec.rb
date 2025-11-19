# frozen_string_literal: true

RSpec.describe 'Idempotency APM Instrumentation' do
  let(:mock_redis) { MockRedis.new }
  let(:redis_pool) { ConnectionPool.new { mock_redis } }
  let(:idempotency) { Idempotency.new }

  before do
    Idempotency.configure do |config|
      config.redis_pool = redis_pool
      config.logger = Logger.new(nil)
    end
  end

  after do
    Idempotency.reset_config
  end

  describe '#with_apm_instrumentation' do
    let(:block_result) { 'test_result' }
    let(:test_block) { -> { block_result } }

    context 'when AppSignal is not enabled' do
      before do
        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = false
        end
      end

      it 'executes the block without instrumentation' do
        result = idempotency.send(:with_apm_instrumentation, 'test.operation', 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end
    end

    context 'when AppSignal is enabled' do
      before do
        stub_const('Appsignal', double('Appsignal'))
        allow(Appsignal).to receive(:instrument).and_yield

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = true
        end
      end

      it 'wraps execution in AppSignal instrumentation' do
        expect(Appsignal).to receive(:instrument).with(
          'test.operation', 'test'
        ).and_yield

        result = idempotency.send(:with_apm_instrumentation, 'test.operation', 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end

      it 'reports errors to AppSignal and re-raises' do
        test_error = StandardError.new('test error')

        expect(Appsignal).to receive(:instrument).with(
          'test.operation', 'test'
        ).and_yield

        expect(Appsignal).to receive(:set_error).with(test_error)

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', 'test') do
            raise test_error
          end
        end.to raise_error(StandardError, 'test error')
      end

      it 'handles exceptions during error reporting gracefully' do
        test_error = StandardError.new('test error')

        expect(Appsignal).to receive(:instrument).with(
          'test.operation', 'test'
        ).and_yield

        expect(Appsignal).to receive(:set_error).with(test_error).and_raise('AppSignal error')

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', 'test') do
            raise test_error
          end
        end.to raise_error('AppSignal error')
      end
    end

    context 'when AppSignal is enabled but not defined' do
      before do
        hide_const('Appsignal')

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = true
        end
      end

      it 'falls back to executing without instrumentation' do
        result = idempotency.send(:with_apm_instrumentation, 'test.operation', 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end
    end
  end
end
