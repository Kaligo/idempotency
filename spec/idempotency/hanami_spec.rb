# frozen_string_literal: true

RSpec.describe Idempotency::Hanami do
  class HanamiApplicationController # rubocop:disable Lint/ConstantDefinitionInBlock
    include Idempotency::Hanami

    def initialize(request)
      @request = request
      @status = nil
      @body = nil
      @headers = {}
    end

    def response
      [status, headers, [body]]
    end

    attr_accessor :request, :body, :headers, :status
  end

  Response = Struct.new(:status, :body, :headers) do # rubocop:disable Lint/ConstantDefinitionInBlock
    def to_a
      [status, headers, body]
    end
  end

  let(:controller) { HanamiApplicationController.new(request) }
  let(:mock_redis) { MockRedis.new }
  let(:mock_controller_action) { double('Controller') }

  subject do
    controller.use_cache(request_identifiers, lock_duration:) do
      mock_controller_action.call
    end
  end

  let(:request_identifiers) { [SecureRandom.hex] }
  let(:lock_duration) { 5 }

  let(:request) do
    double(
      'Hanami::Action::Request',
      request_method: request_method,
      path: '/int/orders/a960e817-3b3c-487c-8db4-7a1d065f52b7',
      env: request_headers
    )
  end
  let(:request_method) { 'POST' }
  let(:request_headers) { { 'HTTP_IDEMPOTENCY_KEY' => idempotency_key } }
  let(:idempotency_key) { SecureRandom.uuid }

  let(:response) { [response_status, response_headers, [response_body]] }
  let(:response_status) { 200 }
  let(:response_body) { { result: 'some_result' }.to_json }
  let(:response_headers) { {} }

  let(:fingerprint) do
    d = Digest::SHA256.new
    d << idempotency_key
    d << request.path
    d << request.request_method
    d << request_identifiers.first
    Base64.strict_encode64(d.digest)
  end
  let(:cache_key) { "idempotency:cached_response:#{fingerprint}" }
  let(:cache) { Idempotency::Cache.new }

  before do
    expect(Idempotency::Cache).to receive(:new).and_return(cache)
    allow(request).to receive(:get_header).with('HTTP_IDEMPOTENCY_KEY').and_return(idempotency_key)
  end

  context 'when request method is not POST' do
    let(:request_method) { 'GET' }

    before do
      expect(mock_controller_action).to receive(:call)
    end

    it 'should not be cached' do
      subject

      expect(cache.get(cache_key)).to be_nil
    end
  end

  context 'when request is cached' do
    let(:cached_headers) { { 'key' => 'value' } }
    let(:cached_status) { 201 }
    let(:cached_body) { { offer_id: SecureRandom.uuid }.to_json }

    before do
      expect(mock_controller_action).not_to receive(:call)
      cache.set(fingerprint, cached_status, cached_headers, cached_body)
    end

    it 'returns cached request' do
      subject

      expect(controller.headers).to eq(cached_headers.merge('Idempotency-Key' => idempotency_key))
      expect(controller.status).to eq(cached_status)
      expect(controller.body).to eq(cached_body)
    end
  end

  context 'when request is not cached' do
    let(:mock_controller_action) do
      double(
        'Controller',
        call: 1.tap do
          controller.status = response_status
          controller.headers = response_headers
          controller.body = response_body
        end
      )
    end

    before do
      expect(cache)
        .to receive(:release_lock)
        .with(fingerprint, be_a(String))
    end

    it 'caches request' do
      subject

      cached_status, cached_headers, cached_body = cache.get(fingerprint)
      expect(cached_status).to eq(response_status)
      expect(cached_body).to eq([response_body])
      expect(cached_headers).to eq({})

      expect(controller.headers).to include({ 'Idempotency-Key' => be_a(String) })
    end
  end

  context 'when response is 5xx' do
    let(:mock_controller_action) do
      double(
        'Controller',
        call: 1.tap do
          controller.status = response_status
          controller.headers = response_headers
          controller.body = response_body
        end
      )
    end
    let(:response_status) { 500 }

    before do
      expect(cache)
        .to receive(:release_lock)
        .with(fingerprint, be_a(String))
    end

    it { expect { subject }.not_to(change { cache.get(fingerprint) }) }
  end

  context 'when there is concurrent request' do
    let(:response) { nil }
    let(:mock_controller_action) { double('Controller', call: 1) }

    it 'returns 409 error and does not cache request' do
      subject

      expect(cache.get(fingerprint)).to be_nil
      expect(controller.status).to eq(409)
      expect(controller.body).to eq(Idempotency.config.response_body.concurrent_error)
    end
  end
end