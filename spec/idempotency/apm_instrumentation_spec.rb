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

    context 'when neither AppSignal nor Sentry is enabled' do
      before do
        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = false
          config.observability.sentry_enabled = false
        end
      end

      it 'executes the block without instrumentation' do
        result = idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end
    end

    context 'when AppSignal is enabled' do
      before do
        stub_const('Appsignal', double('Appsignal'))

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = true
          config.observability.sentry_enabled = false
        end
      end

      it 'wraps execution in AppSignal transaction' do
        expect(Appsignal).to receive(:monitor_transaction).with(
          'test.operation',
          { action: 'test' }
        ).and_yield

        result = idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end

      it 'reports errors to AppSignal and re-raises' do
        test_error = StandardError.new('test error')

        expect(Appsignal).to receive(:monitor_transaction).with(
          'test.operation',
          { action: 'test' }
        ).and_yield

        expect(Appsignal).to receive(:set_error).with(test_error)

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
            raise test_error
          end
        end.to raise_error(StandardError, 'test error')
      end

      it 'handles exceptions during error reporting gracefully' do
        test_error = StandardError.new('test error')

        expect(Appsignal).to receive(:monitor_transaction).with(
          'test.operation',
          { action: 'test' }
        ).and_yield

        expect(Appsignal).to receive(:set_error).with(test_error).and_raise('AppSignal error')

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
            raise test_error
          end
        end.to raise_error('AppSignal error')
      end
    end

    context 'when Sentry is enabled' do
      let(:mock_transaction) { double('Sentry::Transaction', finish: true) }
      let(:mock_scope) { double('Sentry::Scope') }

      before do
        stub_const('Sentry', double('Sentry'))
        allow(Sentry).to receive(:start_transaction).and_return(mock_transaction)
        allow(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        allow(mock_scope).to receive(:set_span)

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = false
          config.observability.sentry_enabled = true
        end
      end

      it 'wraps execution in Sentry transaction' do
        expect(Sentry).to receive(:start_transaction).with(
          name: 'test.operation',
          op: 'idempotency',
          action: 'test'
        ).and_return(mock_transaction)

        expect(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        expect(mock_scope).to receive(:set_span).with(mock_transaction)
        expect(mock_transaction).to receive(:finish)

        result = idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end

      it 'captures exceptions with Sentry and re-raises' do
        test_error = StandardError.new('test error')

        expect(Sentry).to receive(:start_transaction).with(
          name: 'test.operation',
          op: 'idempotency',
          action: 'test'
        ).and_return(mock_transaction)

        expect(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        expect(mock_scope).to receive(:set_span).with(mock_transaction)
        expect(Sentry).to receive(:capture_exception).with(test_error)
        expect(mock_transaction).to receive(:finish)

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
            raise test_error
          end
        end.to raise_error(StandardError, 'test error')
      end

      it 'ensures transaction is finished even when error occurs' do
        test_error = StandardError.new('test error')

        expect(Sentry).to receive(:start_transaction).and_return(mock_transaction)
        expect(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        expect(mock_scope).to receive(:set_span).with(mock_transaction)
        expect(Sentry).to receive(:capture_exception).with(test_error)
        expect(mock_transaction).to receive(:finish)

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
            raise test_error
          end
        end.to raise_error(StandardError, 'test error')
      end
    end

    context 'when AppSignal is enabled but not defined' do
      before do
        hide_const('Appsignal')

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = true
          config.observability.sentry_enabled = false
        end
      end

      it 'falls back to executing without instrumentation' do
        result = idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end
    end

    context 'when Sentry is enabled but not defined' do
      before do
        hide_const('Sentry')

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = false
          config.observability.sentry_enabled = true
        end
      end

      it 'falls back to executing without instrumentation' do
        result = idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end
    end

    context 'when both AppSignal and Sentry are enabled' do
      let(:mock_transaction) { double('Sentry::Transaction', finish: true) }
      let(:mock_scope) { double('Sentry::Scope') }

      before do
        stub_const('Appsignal', double('Appsignal'))
        stub_const('Sentry', double('Sentry'))
        allow(Sentry).to receive(:start_transaction).and_return(mock_transaction)
        allow(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        allow(mock_scope).to receive(:set_span)

        Idempotency.configure do |config|
          config.redis_pool = redis_pool
          config.logger = Logger.new(nil)
          config.observability.appsignal_enabled = true
          config.observability.sentry_enabled = true
        end
      end

      it 'instruments in both AppSignal and Sentry (nested)' do
        # Expect Sentry to be set up (inner layer)
        expect(Sentry).to receive(:start_transaction).with(
          name: 'test.operation',
          op: 'idempotency',
          action: 'test'
        ).and_return(mock_transaction)

        expect(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        expect(mock_scope).to receive(:set_span).with(mock_transaction)
        expect(mock_transaction).to receive(:finish)

        # Expect AppSignal to wrap everything (outer layer)
        expect(Appsignal).to receive(:monitor_transaction).with(
          'test.operation',
          { action: 'test' }
        ).and_yield

        result = idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
          test_block.call
        end

        expect(result).to eq(block_result)
      end

      it 'reports errors to both AppSignal and Sentry' do
        test_error = StandardError.new('test error')

        # Expect Sentry to capture the exception
        expect(Sentry).to receive(:start_transaction).and_return(mock_transaction)
        expect(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        expect(mock_scope).to receive(:set_span).with(mock_transaction)
        expect(Sentry).to receive(:capture_exception).with(test_error)
        expect(mock_transaction).to receive(:finish)

        # Expect AppSignal to also capture the exception
        expect(Appsignal).to receive(:monitor_transaction).and_yield
        expect(Appsignal).to receive(:set_error).with(test_error)

        expect do
          idempotency.send(:with_apm_instrumentation, 'test.operation', action: 'test') do
            raise test_error
          end
        end.to raise_error(StandardError, 'test error')
      end
    end
  end
end
