# frozen_string_literal: true

require_relative '../idempotency'

class Idempotency
  module Hanami
    def use_cache(request_identifiers = [], lock_duration: nil, action: self.class.name)
      response_status, response_headers, response_body = Idempotency.use_cache(
        request, request_identifiers, lock_duration:, action:
      ) do
        yield

        response
      end

      set_response(response_status, response_headers, response_body)
    end

    private

    def set_response(status, headers, body)
      self.status = status
      self.body = body
      self.headers.merge!(headers)
    end
  end
end
