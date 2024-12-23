# frozen_string_literal: true

require 'digest'
require 'redis'
require 'msgpack'

class Idempotency
  class Cache
    class LockConflict < StandardError; end

    DEFAULT_CACHE_EXPIRY = 86_400 # seconds = 1 hour

    COMPARE_AND_DEL_SCRIPT = <<-SCRIPT
        local value = ARGV[1]
        local cached_value = redis.call('GET', KEYS[1])

        if( value == cached_value )
        then
            redis.call('DEL', KEYS[1])
            return value
        end

        return cached_value
    SCRIPT
    COMPARE_AND_DEL_SCRIPT_SHA = Digest::SHA1.hexdigest(COMPARE_AND_DEL_SCRIPT)

    def initialize(config: Idempotency.config)
      @logger = config.logger
      @redis_pool = config.redis_pool
    end

    def get(fingerprint)
      key = response_cache_key(fingerprint)

      cached_response = with_redis do |r|
        r.get(key)
      end

      deserialize(cached_response) if cached_response
    end

    def set(fingerprint, response_status, response_headers, response_body)
      key = response_cache_key(fingerprint)

      with_redis do |r|
        r.set(key, serialize(response_status, response_headers, response_body))
      end
    end

    def with_lock(fingerprint, duration)
      acquired_lock = lock(fingerprint, duration)
      yield
    ensure
      release_lock(fingerprint, acquired_lock) if acquired_lock
    end

    def lock(fingerprint, duration)
      random_value = SecureRandom.hex
      key = lock_key(fingerprint)

      lock_acquired = with_redis do |r|
        r.set(key, random_value, nx: true, ex: duration || Idempotency.config.default_lock_expiry)
      end

      raise LockConflict unless lock_acquired

      random_value
    end

    def release_lock(fingerprint, acquired_lock)
      with_redis do |r|
        lock_released = r.evalsha(COMPARE_AND_DEL_SCRIPT_SHA, keys: [lock_key(fingerprint)], argv: [acquired_lock])
        raise LockConflict if lock_released != acquired_lock
      rescue Redis::CommandError => e
        if e.message.include?('NOSCRIPT')
          # The Redis server has never seen this script before. Needs to run only once in the entire lifetime
          # of the Redis server, until the script changes - in which case it will be loaded under a different SHA
          r.script(:load, COMPARE_AND_DEL_SCRIPT)
          retry
        else
          raise e
        end
      end
    end

    private

    def with_redis(&)
      redis_pool.with(&)
    rescue Redis::ConnectionError, Redis::CannotConnectError => e
      logger.error(e.message)
      nil
    end

    def response_cache_key(fingerprint)
      "idempotency:cached_response:#{fingerprint}"
    end

    def lock_key(fingerprint)
      "idempotency:lock:#{fingerprint}"
    end

    def serialize(response_status, response_headers, response_body)
      cache_data = [response_status, response_headers, response_body]
      MessagePack.pack(cache_data)
    end

    def deserialize(cached_response)
      MessagePack.unpack(cached_response)
    end

    attr_reader :redis_pool, :logger
  end
end
