# frozen_string_literal: true

RSpec.describe Idempotency::Cache do
  Response = Struct.new(:status, :body, :headers) # rubocop:disable Lint/ConstantDefinitionInBlock

  before do
    Idempotency.configure do |config|
      config.redis_pool = ConnectionPool.new { mock_redis }
    end
  end

  after { Idempotency.reset_config }

  let(:cache) { described_class.new }

  let(:mock_redis) { MockRedis.new }
  let(:fingerprint) { SecureRandom.hex }

  describe '#get' do
    subject { cache.get(fingerprint) }

    context 'when there is data' do
      let(:response) { Response.new(response_status, response_body, response_headers) }
      let(:response_status) { 200 }
      let(:response_body) { { result: 'some_result' }.to_json }
      let(:response_headers) { { 'header' => 'valuee' } }

      before do
        cache.set(fingerprint, response)
      end

      it { is_expected.to eq([response_status, response_body, response_headers]) }
    end

    context 'when there is no data' do
      it { is_expected.to be_nil }
    end
  end

  describe '#set' do
    subject { cache.set(fingerprint, response) }

    let(:response) { Response.new(response_status, response_body, response_headers) }
    let(:response_status) { 200 }
    let(:response_body) { { result: 'some_result' }.to_json }
    let(:response_headers) { { 'header' => 'valuee' } }

    it 'sets data in cache correctly' do
      is_expected.to eq('OK')
      expect(cache.get(fingerprint)).to eq([response_status, response_body, response_headers])
    end
  end

  describe '#lock' do
    subject { cache.lock(fingerprint, 10) }

    let(:random_value) { SecureRandom.hex }
    let(:cache_key) { "idempotency:lock:#{fingerprint}" }

    context 'when lock is already owned' do
      before do
        mock_redis.set(cache_key, SecureRandom.hex)
      end

      it { expect { subject }.to raise_error(Idempotency::Cache::LockConflict) }
    end

    context 'when lock is not owned' do
      it { expect { subject }.to change { mock_redis.get(cache_key) }.from(nil).to(be_a(String)) }
    end
  end

  describe '#release_lock' do
    subject { cache.release_lock(fingerprint, acquired_lock) }

    let(:acquired_lock) { SecureRandom.hex }

    before do
      expect(mock_redis)
        .to receive(:evalsha).with(
          Idempotency::Cache::COMPARE_AND_DEL_SCRIPT_SHA,
          keys: ["idempotency:lock:#{fingerprint}"],
          argv: [acquired_lock]
        ).and_return(current_lock)
    end

    context 'when acquired lock is different from current lock' do
      let(:current_lock) { SecureRandom.hex }

      it { expect { subject }.to raise_error(Idempotency::Cache::LockConflict) }
    end

    context 'when acquired lock is the same as current lock' do
      let(:current_lock) { acquired_lock }

      it { expect { subject }.not_to raise_error }
    end
  end
end
