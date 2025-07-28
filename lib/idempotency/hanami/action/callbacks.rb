# frozen_string_literal: true

require 'hanami/utils/class_attribute'
require 'hanami/utils/callbacks'

if Gem.loaded_specs['hanami'] && !Gem::Dependency.new('', '~> 1.3').match?('', Hanami::VERSION)
  raise 'idempotency gem only supports Hanami version 1.3.x'
end

module Hanami
  module Action
    # Before and after callbacks
    #
    # @since 0.1.0
    # @see Hanami::Action::ClassMethods#before
    # @see Hanami::Action::ClassMethods#after
    module Callbacks
      # Override Ruby's hook for modules.
      # It includes callbacks logic
      #
      # @param base [Class] the target action
      #
      # @since 0.1.0
      # @api private
      #
      # @see http://www.ruby-doc.org/core/Module.html#method-i-included
      def self.included(base)
        base.class_eval do
          extend  ClassMethods
          prepend InstanceMethods
        end
      end

      # Callbacks API class methods
      #
      # @since 0.1.0
      # @api private
      module ClassMethods
        # Override Ruby's hook for modules.
        # It includes callbacks logic
        #
        # @param base [Class] the target action
        #
        # @since 0.1.0
        # @api private
        #
        # @see http://www.ruby-doc.org/core/Module.html#method-i-extended
        def self.extended(base)
          base.class_eval do
            include Utils::ClassAttribute

            class_attribute :before_callbacks
            self.before_callbacks = Utils::Callbacks::Chain.new

            class_attribute :after_callbacks
            self.after_callbacks = Utils::Callbacks::Chain.new

            class_attribute :around_callbacks
            self.around_callbacks = Utils::Callbacks::Chain.new
          end
        end

        def append_around(&)
          around_callbacks.append_around(&)
        end

        alias around append_around

        def append_before(*callbacks, &)
          before_callbacks.append(*callbacks, &)
        end

        alias before append_before

        def append_after(*callbacks, &)
          after_callbacks.append(*callbacks, &)
        end

        alias after append_after

        def prepend_before(*callbacks, &)
          before_callbacks.prepend(*callbacks, &)
        end

        def prepend_after(*callbacks, &)
          after_callbacks.prepend(*callbacks, &)
        end
      end

      # Callbacks API instance methods
      #
      # @since 0.1.0
      # @api private
      module InstanceMethods
        # Implements the Rack/Hanami::Action protocol
        #
        # @since 0.1.0
        # @api private
        def call(params)
          _run_before_callbacks(params)
          _run_around_callbacks(params) { super }
          _run_after_callbacks(params)
        end

        private

        def _run_before_callbacks(params)
          self.class.before_callbacks.run(self, params)
        end

        def _run_after_callbacks(params)
          self.class.after_callbacks.run(self, params)
        end

        def _run_around_callbacks(params, &block)
          chain = self.class.around_callbacks.chain
          return block.call if chain.empty?

          execute_around_chain(chain.dup, params, &block)
        end

        # We cannot use Hanami::Utils::Callbacks::Chain#run method
        # since it always call all callbacks sequentially. Instead,
        # we want to have each callback able to control to call the
        # next block or not (in case it want to return early)
        def execute_around_chain(chain, params, &block)
          if chain.empty?
            block.call
          else
            callback = chain.shift
            callback.call(self, params) { execute_around_chain(chain, params, &block) }
          end
        end
      end
    end
  end
end
