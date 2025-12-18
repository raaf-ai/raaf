# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Raaf
  module Rails
    module Generators
      ##
      # Generator for installing RAAF Rails migrations
      #
      # @example Run the generator
      #   rails generate raaf:rails:install
      #
      # @example Run with options
      #   rails generate raaf:rails:install --skip-tracing
      #   rails generate raaf:rails:install --skip-eval
      #
      class InstallGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        class_option :skip_tracing, type: :boolean, default: false,
                     desc: "Skip tracing migrations (trace_records, span_records)"
        class_option :skip_eval, type: :boolean, default: false,
                     desc: "Skip continuous evaluation migrations"

        def self.next_migration_number(dirname)
          ::ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def create_migrations
          say "Installing RAAF Rails migrations...", :green

          unless options[:skip_tracing]
            copy_tracing_migrations
          end

          unless options[:skip_eval]
            copy_eval_migrations
          end

          say ""
          say "Migrations installed successfully!", :green
          say ""
          say "Next steps:", :yellow
          say "  1. Run migrations: rails db:migrate"
          say "  2. Mount the engine in routes.rb if not already mounted:"
          say "     mount RAAF::Rails::Engine, at: '/raaf'"
          say ""
        end

        private

        def copy_tracing_migrations
          say "Copying tracing migrations...", :cyan

          # Tracing migrations from rails gem
          # Path: from lib/generators/raaf/rails/ up to rails/, then down to db/migrate/
          tracing_migrations_path = File.expand_path("../../../../db/migrate", __dir__)

          copy_migrations_from_path(tracing_migrations_path, "tracing")
        end

        def copy_eval_migrations
          say "Copying continuous evaluation migrations...", :cyan

          # Eval migrations from eval gem
          # Path: from lib/generators/raaf/rails/ up to raaf/, then down to eval/db/migrate/
          eval_migrations_path = File.expand_path("../../../../../eval/db/migrate", __dir__)

          copy_migrations_from_path(eval_migrations_path, "eval")
        end

        def copy_migrations_from_path(source_path, type)
          unless Dir.exist?(source_path)
            say "  No #{type} migrations found at #{source_path}", :yellow
            return
          end

          Dir.glob("#{source_path}/*.rb").sort.each do |migration_file|
            # Extract migration name without numeric prefix
            original_filename = File.basename(migration_file)
            migration_name = original_filename.sub(/^\d+_/, "")

            if migration_exists?(migration_name)
              say "  skip  #{migration_name} (already exists)", :yellow
            else
              # Generate new timestamp for migration
              timestamp = self.class.next_migration_number("db/migrate")
              destination = "db/migrate/#{timestamp}_#{migration_name}"

              # Copy the migration file
              copy_file migration_file, destination

              say "  create  #{timestamp}_#{migration_name}", :green
            end
          end
        end

        def migration_exists?(migration_name)
          # Check if migration already exists with any timestamp
          migrations_dir = File.join(destination_root, "db/migrate")
          return false unless Dir.exist?(migrations_dir)

          Dir.glob("#{migrations_dir}/*_#{migration_name}").any?
        end
      end
    end
  end
end
