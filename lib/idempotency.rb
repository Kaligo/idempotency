# frozen_string_literal: true

require 'dry-configurable'
require 'json'
require 'base64'
require_relative 'idempotency/cache'
require_relative 'idempotency/constants'
require_relative 'idempotency/instrumentation/statsd_listener'
require 'dry-monitor'

class Idempotency
  extend Dry::Configurable
  @monitor = Monitor.new

  def self.notifier
    @monitor.synchronize do
      @notifier ||= Dry::Monitor::Notifications.new(:idempotency_gem).tap do |n|
        Events::ALL_EVENTS.each { |event| n.register_event(event) }
      end
    end
  end

  setting :redis_pool
  setting :logger
  setting :instrumentation_listeners, default: []
  setting :metrics do
    setting :namespace
    setting :statsd_client
  end

  setting :default_lock_expiry, default: 300 # 5 minutes
  setting :idempotent_methods, default: %w[POST PUT PATCH DELETE]
  setting :idempotent_statuses, default: (200..299).to_a + (400..499).to_a

  setting :response_body do
    setting :concurrent_error, default: {
      errors: [{ message: 'Request conflicts with another likely concurrent request.' }]
    }.to_json
  end

  def self.configure
    super

    if config.metrics.statsd_client
      config.instrumentation_listeners << Idempotency::Instrumentation::StatsdListener.new(
        config.metrics.statsd_client,
        config.metrics.namespace
      )
    end

    config.instrumentation_listeners.each(&:setup_subscriptions)
  end

  def initialize(config: Idempotency.config, cache: Cache.new(config:))
    @config = config
    @cache = cache
  end

  def self.use_cache(request, request_identifiers, lock_duration: nil, action: nil, &blk)
    new.use_cache(request, request_identifiers, lock_duration:, action:, &blk)
  end

  def use_cache(request, request_identifiers, lock_duration: nil, action: nil) # rubocop:disable Metrics/AbcSize
    duration_start = Process.clock_gettime(::Process::CLOCK_MONOTONIC)

    return yield unless cache_request?(request)

    request_headers = request.env
    idempotency_key = unquote(request_headers[Constants::RACK_HEADER_KEY] || SecureRandom.hex)

    fingerprint = calculate_fingerprint(request, idempotency_key, request_identifiers)

    cached_response = cache.get(fingerprint)

    if (cached_status, cached_headers, cached_body = cached_response)
      cached_headers.merge!(Constants::HEADER_KEY => idempotency_key)
      instrument(Events::CACHE_HIT, request:, action:, duration: calculate_duration(duration_start))

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

    instrument(Events::CACHE_MISS, request:, action:, duration: calculate_duration(duration_start))
    [response_status, response_headers, response_body]
  rescue Idempotency::Cache::LockConflict
    instrument(Events::LOCK_CONFLICT, request:, action:, duration: calculate_duration(duration_start))
    [409, {}, config.response_body.concurrent_error]
  end

  private

  attr_reader :config, :cache

  def instrument(event_name, **metadata)
    Idempotency.notifier.instrument(event_name, **metadata)
  end

  def calculate_duration(start_time)
    Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time
  end

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
    config.idempotent_methods.include?(request.request_method)
  end

  def cache_response?(response_status)
    config.idempotent_statuses.include?(response_status)
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
