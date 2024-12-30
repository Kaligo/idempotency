# frozen_string_literal: true

require 'dry-configurable'
require 'json'
require 'base64'
require_relative 'idempotency/cache'
require_relative 'idempotency/constants'

class Idempotency
  extend Dry::Configurable

  setting :redis_pool
  setting :logger
  setting :default_lock_expiry, default: 300 # 5 minutes
  setting :idempotent_methods, default: %w[POST PUT PATCH DELETE]

  setting :response_body do
    setting :concurrent_error, default: {
      errors: [{ message: 'Request conflicts with another likely concurrent request.' }]
    }.to_json
  end

  def initialize(config: Idempotency.config, cache: Cache.new(config:))
    @config = config
    @cache = cache
  end

  def self.use_cache(request, request_identifiers, lock_duration: nil, &blk)
    new.use_cache(request, request_identifiers, lock_duration:, &blk)
  end

  def use_cache(request, request_identifiers, lock_duration:) # rubocop:disable Metrics/AbcSize
    return yield unless cache_request?(request)

    request_headers = request.env
    idempotency_key = unquote(request_headers[Constants::RACK_HEADER_KEY] || SecureRandom.hex)

    fingerprint = calculate_fingerprint(request, idempotency_key, request_identifiers)

    cached_response = cache.get(fingerprint)

    if (cached_status, cached_headers, cached_body = cached_response)
      cached_headers.merge!(Constants::HEADER_KEY => idempotency_key)
      return [cached_status, cached_headers, cached_body]
    end

    lock_duration ||= config.default_lock_expiry
    response_status, response_headers, response_body = cache.with_lock(fingerprint, lock_duration) do
      yield
    end

    if cache_response?(response_status)
      cache.set(fingerprint, response_status, response_headers, response_body)
      response_headers.merge!({ Constants::HEADER_KEY => idempotency_key })
    end

    [response_status, response_headers, response_body]
  rescue Idempotency::Cache::LockConflict
    [409, {}, config.response_body.concurrent_error]
  end

  private

  attr_reader :config, :cache

  def calculate_fingerprint(request, idempotency_key, request_identifiers)
    d = Digest::SHA256.new
    d << idempotency_key
    d << request.path
    d << request.request_method

    request_identifiers.each do |identifier|
      d << identifier
    end

    Base64.strict_encode64(d.digest)
  end

  def cache_request?(request)
    request.request_method == 'POST'
  end

  def cache_response?(response_status)
    (200..299).include?(response_status) || (400..499).include?(response_status)
  end

  def unquote(str)
    double_quote = '"'
    if str.start_with?(double_quote) && str.end_with?(double_quote)
      str[1..-2]
    else
      str
    end
  end
end
