# frozen_string_literal: true

class Idempotency
  class Constants
    RACK_HEADER_KEY = 'HTTP_IDEMPOTENCY_KEY'
    HEADER_KEY = 'Idempotency-Key'
  end

  module Events
    ALL_EVENTS = [
      CACHE_HIT = :cache_hit,
      CACHE_MISS = :cache_miss,
      LOCK_CONFLICT = :lock_conflict
    ].freeze
  end
end
