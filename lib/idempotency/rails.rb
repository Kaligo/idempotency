# frozen_string_literal: true

require_relative '../idempotency'

class Idempotency
  module Rails
    def use_cache(request_identifiers = [], lock_duration: nil, action: "#{controller_name}##{action_name}")
      response_status, response_headers, response_body = Idempotency.use_cache(
        request, request_identifiers, lock_duration:, action:
      ) do
        yield

        [response.status, response.headers, response.body]
      end

      set_response(response_status, response_headers, response_body)
    end

    private

    def set_response(status, headers, body)
      response.status = status
      response.body = body
      headers.each do |key, value|
        response.set_header(key, value)
      end
    end
  end
end
