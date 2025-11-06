# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Configuration class for RAAF Eval UI engine
      #
      # Provides configurable authentication, authorization, and layout settings
      # that allow the engine to integrate with different Rails applications.
      #
      # @example Configure authentication
      #   RAAF::Eval::UI.configure do |config|
      #     config.authentication_method = :authenticate_admin!
      #     config.current_user_method = :current_admin
      #   end
      #
      class Configuration
        # @return [Symbol] Name of authentication method to call (default: :authenticate_user!)
        attr_accessor :authentication_method

        # @return [Symbol] Name of current user method (default: :current_user)
        attr_accessor :current_user_method

        # @return [Proc, nil] Authorization callback for span access
        attr_accessor :authorize_span_access

        # @return [String, nil] Layout to use (defaults to engine's layout)
        attr_accessor :layout

        # @return [Boolean] Whether to inherit host app's assets
        attr_accessor :inherit_assets

        def initialize
          @authentication_method = :authenticate_user!
          @current_user_method = :current_user
          @authorize_span_access = nil
          @layout = nil
          @inherit_assets = true
        end
      end

      class << self
        # @return [Configuration] The current configuration
        def configuration
          @configuration ||= Configuration.new
        end

        ##
        # Configure RAAF Eval UI
        #
        # @yield [Configuration] The configuration object
        # @return [Configuration]
        #
        # @example
        #   RAAF::Eval::UI.configure do |config|
        #     config.authentication_method = :authenticate_admin!
        #     config.authorize_span_access = ->(user, span) { user.admin? }
        #   end
        #
        def configure
          yield(configuration)
        end

        # Reset configuration (useful for testing)
        # @api private
        def reset_configuration!
          @configuration = Configuration.new
        end
      end
    end
  end
end
