# frozen_string_literal: true

RSpec.describe Idempotency::Rails do
  class ApplicationController # rubocop:disable Lint/ConstantDefinitionInBlock
    include Idempotency::Rails

    def initialize(request, response)
      @request = request
      @response = response
    end

    def render(json:, status:)
      response.body = json
      response.status = status
    end

    private

    attr_reader :request, :response
  end

  Response = Struct.new(:status, :body, :headers) do # rubocop:disable Lint/ConstantDefinitionInBlock
    def set_header(key, value)
      headers[key] = value
    end
  end

  let(:controller) { ApplicationController.new(request, response) }
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
      'ActionDispatch::Request',
      method: request_method,
      path: '/int/orders/a960e817-3b3c-487c-8db4-7a1d065f52b7',
      headers: request_headers
    )
  end
  let(:request_method) { 'POST' }
  let(:request_headers) { { 'Idempotency-Key' => idempotency_key } }
  let(:idempotency_key) { SecureRandom.uuid }

  let(:response) { Response.new(response_status, response_body, response_headers) }
  let(:response_status) { 200 }
  let(:response_body) { { result: 'some_result' }.to_json }
  let(:response_headers) { {} }

  let(:fingerprint) do
    d = Digest::SHA256.new
    d << idempotency_key
    d << request.path
    d << request.method
    d << request_identifiers.first
    Base64.strict_encode64(d.digest)
  end
  let(:cache_key) { "idempotency:cached_response:#{fingerprint}" }
  let(:cache) { Idempotency.cache }

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
    let(:response) { Response.new(nil, nil, {}) }
    let(:cached_headers) { { 'key' => 'value' } }
    let(:cached_status) { 201 }
    let(:cached_body) { { offer_id: SecureRandom.uuid }.to_json }

    before do
      expect(mock_controller_action).not_to receive(:call)
      cache.set(fingerprint, Response.new(cached_status, cached_body, cached_headers))
    end

    it 'returns cached request' do
      subject

      expect(response.headers).to eq(cached_headers)
      expect(response.status).to eq(cached_status)
      expect(response.body).to eq(cached_body)
    end
  end

  context 'when request is not cached' do
    let(:mock_controller_action) { double('Controller', call: 1) }
    let(:response) { Response.new(response_status, response_body, response_headers) }

    before do
      expect(Idempotency.cache)
        .to receive(:release_lock)
        .with(fingerprint, be_a(String))
    end

    it 'caches request' do
      subject

      cached_status, cached_body, cached_headers = cache.get(fingerprint)
      expect(cached_status).to eq(response_status)
      expect(cached_body).to eq(response_body)
      expect(cached_headers).to include({ 'Idempotency-Key' => be_a(String) })
    end
  end

  context 'when response is 5xx' do
    let(:mock_controller_action) { double('Controller', call: 1) }
    let(:response) { Response.new(response_status, response_body, response_headers) }
    let(:response_status) { 500 }

    before do
      expect(Idempotency.cache)
        .to receive(:release_lock)
        .with(fingerprint, be_a(String))
    end

    it { expect { subject }.not_to(change { cache.get(fingerprint) }) }
  end

  context 'when there is concurrent request' do
    let(:response) { Response.new(nil, nil, nil) }
    let(:mock_controller_action) { double('Controller', call: 1) }

    it 'returns 409 error and does not cache request' do
      subject

      expect(cache.get(fingerprint)).to be_nil
      expect(response.status).to eq(409)
      expect(response.body).to eq(Idempotency.config.response_body.concurrent_error)
    end
  end
end
