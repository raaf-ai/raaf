# frozen_string_literal: true

require "digest"

# Builds the test database the engine's models read.
#
# The schema is spread across two gems -- raaf-eval owns the evaluation tables,
# raaf-rails the tracing ones -- and both numbered their migrations from 001, so
# a single MigrationContext over both directories would see version 1 twice and
# silently skip the second. The migration classes are applied directly instead,
# against a schema that is dropped and rebuilt whenever the migration files
# change. The digest below is what makes a repeat run cheap.
module SchemaLoader
  MIGRATION_PATHS = [
    File.expand_path("../../eval/db/migrate", __dir__),
    File.expand_path("../db/migrate", __dir__)
  ].freeze

  FINGERPRINT_TABLE = "raaf_spec_schema_fingerprint"

  class << self
    # @return [Boolean] whether the database is usable; false means the model,
    #   request and feature specs will be skipped rather than each failing with
    #   the same connection error.
    def load!
      connection.verify!
      rebuild! unless current?
      true
    rescue StandardError => e
      warn "[raaf-rails specs] no test database (#{e.class}: #{e.message}); " \
           "specs needing one will be skipped"
      false
    end

    private

    def connection
      ActiveRecord::Base.connection
    end

    def migration_files
      MIGRATION_PATHS.flat_map { |path| Dir[File.join(path, "*.rb")].sort }
    end

    def fingerprint
      @fingerprint ||= Digest::SHA256.hexdigest(migration_files.map { |f| File.read(f) }.join)
    end

    def current?
      return false unless connection.table_exists?(FINGERPRINT_TABLE)

      connection.select_value("SELECT digest FROM #{FINGERPRINT_TABLE} LIMIT 1") == fingerprint
    end

    def rebuild!
      connection.execute("DROP SCHEMA public CASCADE")
      connection.execute("CREATE SCHEMA public")
      connection.schema_cache.clear!

      ActiveRecord::Migration.verbose = false
      migration_files.each { |file| apply(file) }

      connection.execute("CREATE TABLE #{FINGERPRINT_TABLE} (digest text)")
      connection.execute("INSERT INTO #{FINGERPRINT_TABLE} (digest) VALUES (#{connection.quote(fingerprint)})")
      ActiveRecord::Base.descendants.each(&:reset_column_information)
    end

    # Named rather than discovered: the engine registers "RAAF" as an acronym,
    # so 001_create_raaf_evaluation_policies.rb camelizes back to the
    # CreateRAAFEvaluationPolicies the file actually defines.
    def apply(file)
      load file
      File.basename(file, ".rb").sub(/\A\d+_/, "").camelize.constantize.new.migrate(:up)
    end
  end
end
