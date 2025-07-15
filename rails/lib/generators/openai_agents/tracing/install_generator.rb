# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module OpenAIAgents
  module Tracing
    # Rails generator for installing OpenAI Agents tracing
    #
    # This generator sets up everything needed to use the OpenAI Agents
    # tracing engine in a Rails application:
    #
    # - Creates database migrations for traces and spans
    # - Generates an initializer for configuration
    # - Adds mount point to routes (optional)
    # - Copies any needed assets
    #
    # ## Usage
    #
    #   rails generate openai_agents:tracing:install
    #
    # ## Options
    #
    # --skip-routes     Skip adding mount point to routes.rb
    # --skip-initializer  Skip creating initializer file
    # --mount-path      Custom mount path (default: /tracing)
    #
    # @example Basic installation
    #   rails generate openai_agents:tracing:install
    #   rails db:migrate
    #
    # @example Custom mount path
    #   rails generate openai_agents:tracing:install --mount-path=/admin/tracing
    #
    # @example Skip route modification
    #   rails generate openai_agents:tracing:install --skip-routes
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      # Explicitly set the namespace to make Rails find it with desired command
      namespace "openai_agents:tracing:install"

      source_root File.expand_path("templates", __dir__)

      class_option :skip_routes, type: :boolean, default: false,
                                 desc: "Skip adding mount point to routes.rb"
      class_option :skip_initializer, type: :boolean, default: false,
                                      desc: "Skip creating initializer file"
      class_option :mount_path, type: :string, default: "/tracing",
                                desc: "Mount path for the tracing engine"

      desc "Install OpenAI Agents tracing engine"

      def create_migrations
        migration_template "create_openai_agents_tracing_tables.rb.erb",
                           "db/migrate/create_openai_agents_tracing_tables.rb",
                           migration_version: migration_version
      end

      def create_initializer
        return if options[:skip_initializer]

        template "initializer.rb.erb", "config/initializers/openai_agents_tracing.rb"
      end

      def add_inflections
        application_file = "config/application.rb"

        # Check if inflection already exists
        if File.read(application_file).include?('inflect.acronym "OpenAI"')
          say "OpenAI inflection already exists, skipping...", :yellow
          return
        end

        # Add inflection rule after requiring rails/all
        inflection_code = <<~RUBY

          # Configure inflections before anything else
          require "active_support/inflector"
          ActiveSupport::Inflector.inflections(:en) do |inflect|
            inflect.acronym "OpenAI"
          end

        RUBY

        inject_into_file application_file, inflection_code, after: "require \"rails/all\"\n"
        say "Added OpenAI inflection rules to config/application.rb", :green
      end

      def ensure_gem_required
        environment_file = "config/environment.rb"

        # Check if gem is already required
        if File.read(environment_file).include?("require 'openai_agents'")
          say "OpenAI Agents gem already required, skipping...", :yellow
          return
        end

        # Add require statements before Rails.application.initialize!
        require_code = <<~RUBY

          # Ensure the gem is loaded
          require 'openai_agents'
          require 'openai_agents/tracing/engine'

        RUBY

        inject_into_file environment_file, require_code, before: "# Initialize the Rails application."
        say "Added gem requires to config/environment.rb", :green
      end

      def add_routes
        return if options[:skip_routes]

        route_line = "  mount OpenAIAgents::Tracing::Engine => '#{options[:mount_path]}'"

        # Check if route already exists
        if File.read("config/routes.rb").include?("OpenAIAgents::Tracing::Engine")
          say "Route already exists, skipping...", :yellow
          return
        end

        # Add route inside Rails.application.routes.draw block
        inject_into_file "config/routes.rb", after: "Rails.application.routes.draw do\n" do
          "#{route_line}\n"
        end

        say "Added route: #{route_line}", :green
      end

      def show_installation_instructions
        say <<~INSTRUCTIONS

          🎉 OpenAI Agents Tracing installation complete!

          Next steps:
          1. Run migrations:
             rails db:migrate

          2. Restart your Rails server to load the inflection rules:
             rails restart  # or restart your Docker container

          3. The tracing configuration has been added to:
             config/initializers/openai_agents_tracing.rb
          #{"   "}
             You can edit this file to customize sampling rate, batch size,
             and other tracing options.

          4. Visit #{options[:mount_path]} in your browser to view traces

          📖 For more information, see the documentation at:
             https://github.com/openai/agents-ruby#tracing

        INSTRUCTIONS
      end

      private

      # Get the next migration number
      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      # Migration version for Rails compatibility
      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
