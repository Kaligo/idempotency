# frozen_string_literal: true

require 'hanami-controller'
require_relative '../../../lib/hanami/action/callbacks'
require_relative '../../../lib/hanami/utils/callbacks'

RSpec.describe Hanami::Action::Callbacks do
  describe 'callbacks' do
    let(:action) { CallbacksAction.new }

    class CallbacksAction # rubocop:disable Lint/ConstantDefinitionInBlock
      include Hanami::Action::Callbacks

      def self.reset!
        @before_callbacks = Hanami::Utils::Callbacks::Chain.new
        @after_callbacks = Hanami::Utils::Callbacks::Chain.new
        @around_callbacks = Hanami::Utils::Callbacks::Chain.new
      end

      def call(params); end
    end

    before do
      CallbacksAction.reset!
    end

    describe 'around callbacks' do
      it 'executes around callbacks in the correct order' do
        executed_order = []

        CallbacksAction.class_eval do
          around do |_params, action|
            executed_order << :before_first
            action.call
            executed_order << :after_first
          end

          around do |_params, action|
            executed_order << :before_second
            action.call
            executed_order << :after_second
          end

          def call(executed_order)
            executed_order << :action
          end
        end

        action.call(executed_order)

        expect(executed_order).to eq(
          %i[
            before_first
            before_second
            action
            after_second
            after_first
          ]
        )
      end

      it 'allows early return from around callbacks' do
        executed_order = []

        CallbacksAction.class_eval do
          around do |_params, _action|
            executed_order << :before_first
          end

          around do |_params, action|
            executed_order << :before_second
            action.call
            executed_order << :after_second
          end

          def call(executed_order)
            executed_order << :action
          end
        end

        action.call(executed_order)

        expect(executed_order).to eq(%i[before_first])
      end
    end
  end
end
