# frozen_string_literal: true

require_relative '../../idempotency'

class Idempotency
  module Instrumentation
    class StatsdListener
      EVENT_NAME_TO_METRIC_MAPPINGS = {
        Events::CACHE_HIT => 'idempotency_cache_hit_count',
        Events::CACHE_MISS => 'idempotency_cache_miss_count',
        Events::LOCK_CONFLICT => 'idempotency_lock_conflict_count'
      }.freeze

      def initialize(statsd_client, namespace = nil)
        @statsd_client = statsd_client
        @namespace = namespace
      end

      def setup_subscriptions
        EVENT_NAME_TO_METRIC_MAPPINGS.each do |event_name, metric|
          Idempotency.notifier.subscribe(event_name) do |event|
            send_metric(metric, event.payload)
          end
        end
      end

      private

      attr_reader :namespace, :statsd_client

      def send_metric(metric_name, event_data)
        action = event_data[:action] || "#{event_data[:request].request_method}:#{event_data[:request].path}"
        tags = ["action:#{action}"]
        tags << "namespace:#{@namespace}" if @namespace

        @statsd_client.increment(metric_name, tags:)
        @statsd_client.histogram(
          'idempotency_cache_duration_seconds', event_data[:duration], tags: tags + ["metric:#{metric_name}"]
        )
      end
    end
  end
end
