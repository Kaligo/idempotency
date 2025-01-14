# frozen_string_literal: true

require 'idempotency/cache'

class Idempotency
  module Testing
    module Helpers
      def self.included(_base)
        return unless defined?(MockRedis)

        MockRedis.class_eval do
          def evalsha(sha, keys:, argv:)
            return unless sha == Idempotency::Cache::COMPARE_AND_DEL_SCRIPT_SHA

            value = argv[0]
            cached_value = get(keys[0])

            if value == cached_value
              del(keys[0])
              value
            else
              cached_value
            end
          end
        end
      end
    end
  end
end
