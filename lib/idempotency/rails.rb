# frozen_string_literal: true

require 'base64'
require_relative 'constants'

module Idempotency
  module Rails
    def use_cache(request_identifiers = [], lock_duration: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      return yield unless cache_request?(request)

      cache = Idempotency.cache

      idempotency_key = unquote(request.headers[Constants::HEADER_KEY] || SecureRandom.hex)

      fingerprint = calculate_fingerprint(request, idempotency_key, request_identifiers)

      cached_response = cache.get(fingerprint)
      return set_response(response, *cached_response) if cached_response

      cache.with_lock(fingerprint, lock_duration || Idempotency.config.default_lock_expiry) do
        yield
      end

      if cache_response?(response)
        response.headers[Constants::HEADER_KEY] = idempotency_key
        cache.set(fingerprint, response) if cache_response?(response)
      end
    rescue Idempotency::Cache::LockConflict
      render(**duplicated_concurrent_request_error)
    end

    def calculate_fingerprint(request, idempotency_key, request_identifiers)
      d = Digest::SHA256.new
      d << idempotency_key
      d << request.path
      d << request.method

      request_identifiers.each do |identifier|
        d << identifier
      end

      Base64.strict_encode64(d.digest)
    end

    private

    def set_response(response, status, body, headers)
      response.status = status
      response.body = body
      headers.each do |key, value|
        response.set_header(key, value)
      end
    end

    def cache_request?(request)
      request.method == 'POST'
    end

    def cache_response?(response)
      (200..299).include?(response.status) || (400..499).include?(response.status)
    end

    def duplicated_concurrent_request_error
      {
        json: Idempotency.config.response_body.concurrent_error,
        status: 409
      }
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
end
