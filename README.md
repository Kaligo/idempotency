# Idempotency

## Installation

Add this line to your Gemfile:

```ruby
gem 'idempotency'
```

## Configuration

```ruby
Idempotency.configure do |config|
  # Required configurations
  config.redis_pool = ConnectionPool.new(size: 5) { Redis.new }
  config.logger = Logger.new # Use Rails.logger or Hanami.logger based on your framework

  # Optional configurations

  # Handles concurrent request locks. If a request with the same idempotency key is made before the first one finishes,
  # it will be blocked with a 409 status until the lock expires. Ensure this value is greater than the maximum response time.
  config.default_lock_expiry = 60

  # Match this config to your application's error format
  config.response_body.concurrent_error = {
    errors: [{ message: 'Concurrent requests occurred' }]
  }

  config.idempotent_methods = %w[POST PUT PATCH]
  config.idempotent_statuses = (200..299).to_a
end
```

## Usage

### Rails

Add this to your controller:

```ruby
require 'idempotency/rails'

class UserController < ApplicationController
  include Idempotency::Rails

  around_action :use_cache, except: %i[create]

  # Configure lock_duration for specific actions
  around_action :idempotency_cache, only: %i[update]

  private

  def idempotency_cache
    use_cache(lock_duration: 360) do # Lock for 6 minutes
      yield
    end
  end
end
```

### Hanami

Add this to your controller:

```ruby
require 'idempotency/hanami'

class Api::Controllers::Users::Create
  include Hanami::Action
  include Idempotency::Hanami

  around do |params, block|
    use_cache(request_ids, lock_duration: 360) do
      block.call
    end
  end
end
```

### Manual

For custom implementations or if not using Rails or Hanami:

```ruby
status, headers, body = Idempotency.use_cache(request, request_identifiers, lock_duration: 60) do
  yield
end

# Render your response
```

### Testing

For those using `mock_redis` gem, some methods that `idempotency` gem uses are not implemented (e.g. eval, evalsha), and this could cause test cases to fail. To get around this, the gem has a monkeypatch over `mock_redis` gem to override the missing methods. To use it, simply add following lines to your `spec_helper.rb`:

```ruby
RSpec.configure do |config|
  config.include Idempotency::Testing::Helpers
end
```

### Instrumentation

The gem supports instrumentation through StatsD. It tracks the following metrics:

- `idempotency_cache_hit_count` - Incremented when a cached response is found
- `idempotency_cache_miss_count` - Incremented when no cached response exists
- `idempotency_lock_conflict_count` - Incremented when concurrent requests conflict
- `idempotency_cache_duration_seconds` - Histogram of operation duration

Each metric includes tags:
- `action` - Either the specified action name or `"{HTTP_METHOD}:{PATH}"`
- `namespace` - Your configured namespace (if provided)
- `metric` - The metric name (for duration histogram only)

To enable above instrumentation, configure a StatsD listener:

```ruby
statsd_client = Datadog::Statsd.new
statsd_listener = Idempotency::Instrumentation::StatsdListener.new(
  statsd_client,
  'my_service_name'
)

Idempotency.configure do |config|
  config.instrumentation_listeners = [statsd_listener]
end
```

