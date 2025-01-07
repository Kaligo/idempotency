# Idempotency

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'idempotency'
```

## Configuration

```ruby
Idempotency.configure do |config|
  # required configurations

  config.redis_pool = ConnectionPool.new(size: 5) { Redis.new }
  config.logger = Logger.new # could be Rails.logger or Hanami.logger depending on the framework

  # optional configurations

  # This configuration handles concurrent request locks.
  # When a request starts, a lock for the request will be created. If the request
  # hasn't finished, but there is another request with the same idempotency key,
  # it will be blocked with a 409 status until the lock expires. If the lock has expired,
  # the concurrent request will not be blocked even if it has the same
  # idempotency key.
  # Please ensure that this value is greater than the maximum response time of the request.
  config.default_lock_expiry = 60

  # Set this config to match the error format of your application
  config.response_body.concurrent_error = {
    errors: [{ message: 'Concurrent requests occurred' }]
  }

  config.idempotent_methods = %[POST PUT PATCH]
  config.idempotent_statuses = (200..299).to_a
end
```

## Usage

### Rails

Add the following code to your controller:

```ruby
require 'idempotency/rails'

class UserController < ApplicationController
  include Idempotency::Rails

  around_action :use_cache, except: %i(create)

  # or if we want to configure lock_duration for each action

  around_action :idempotency_cache, only: %i(update)

  private

    def idempotency_cache
      use_cache(lock_duration: 360) do # lock for 6 minutes
        yield
      end
    end
end
```

### Hanami

Add the following code to your controller:

```ruby
require 'idempotency/hanami'

class Api::Controllers::Users::Create
  include Hanami::Action
  include Idempotency::Hanami

  around do |params, block|
    # check the params if necessary

    use_cache(request_ids, lock_duration: 360) do
      block.call
    end
  end
end
```

### Manual

If you don't use either Rails or Hanami, or require more customization than what
the gem supplies, you can implement your own method with the below code:

```ruby
status, headers, body = Idempotency.use_cache(request, request_identifiers, lock_duration: 60) do
  yield
end

# render your own response
```
