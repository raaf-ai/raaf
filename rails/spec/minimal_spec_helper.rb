# frozen_string_literal: true

require "bundler/setup"

# Add parent gems to load path if in development
parent_dir = File.expand_path("../..", __dir__)
core_lib = File.join(parent_dir, "core/lib")

$LOAD_PATH.unshift(core_lib) if File.directory?(core_lib)

# Only require core (skip memory and tracing to avoid matrix dependency)
require "raaf-core"

# Require testing support
require "tempfile"
require "tmpdir"
# Removed ostruct - using custom mock classes instead
require "pathname"
require "logger"

# Mock Rails module to satisfy dependencies
module Rails
  VERSION = Struct.new(:string).new("7.0.0")

  class Engine
    # Basic Engine implementation for testing
    def self.isolate_namespace(mod)
      # No-op for testing
    end

    MockConfig = Struct.new(:generators, :assets, :autoload_paths, :eager_load_paths, :after_initialize, :to_prepare, :i18n)
    MockGenerators = Struct.new(:test_framework)
    MockAssets = Struct.new(:enabled, :paths, :precompile)
    MockI18n = Struct.new(:load_path)

    def self.config
      @config ||= MockConfig.new(
        MockGenerators.new,
        MockAssets.new(true, [], []),
        [],
        [],
        [],
        [],
        MockI18n.new([])
      )
    end

    def self.initializer(name, opts = {}, &block)
      # No-op for testing
    end

    MockRoutes = Struct.new(:draw)

    def self.routes
      @routes ||= MockRoutes.new(->(&block) {})
    end
  end

  class Application
    MockAppConfig = Struct.new(:root, :assets)
    MockSimpleRoutes = Struct.new(:draw)

    def self.config
      @config ||= MockAppConfig.new(
        Pathname.new(Dir.pwd),
        Engine::MockAssets.new(true, [], [])
      )
    end

    def self.routes
      @routes ||= MockSimpleRoutes.new
    end

    def self.logger
      @logger ||= Logger.new(IO::NULL)
    end
  end

  def self.application
    @application ||= Application.new
  end

  def self.env
    "test"
  end

  def self.logger
    application.logger
  end
end

# Mock ActionController for basic Rails compatibility
module ActionController
  class Base
    # Base controller class for testing
    def self.protect_from_forgery(*args)
      # No-op for testing
    end

    def self.before_action(*args)
      # No-op for testing
    end

    def self.rescue_from(*args)
      # No-op for testing
    end

    def self.helper_method(*args)
      # No-op for testing
    end

    def self.include(mod)
      # No-op for testing
    end
  end
end

# Mock ActiveRecord for basic Rails compatibility
module ActiveRecord
  class Base
    MockConnection = Struct.new(:execute)

    def self.connection
      @connection ||= MockConnection.new(->(_sql) {})
    end

    def self.establish_connection(_config)
      # No-op for testing
    end

    # Add query methods
    class WhereChain
      def initialize(model)
        @model = model
      end

      def not(*args)
        @model
      end
    end

    def self.where(*args)
      if args.empty?
        WhereChain.new(self)
      else
        self
      end
    end

    def self.joins(*args)
      self
    end

    def self.limit(*args)
      self
    end

    def self.order(*args)
      self
    end

    def self.page(*args)
      self
    end

    def self.per(*args)
      self
    end

    def self.select(*args)
      self
    end

    def self.count(*args)
      0
    end

    def self.group(*args)
      self
    end

    def self.sum(*args)
      0
    end

    def self.average(*args)
      nil
    end

    def self.find_by(*args)
      nil
    end

    def self.group_by_day(*args)
      Hash.new(0)
    end
  end

  module Schema
    def self.define(&block)
      # No-op for testing
    end
  end
end

# Mock ActiveSupport for Rails compatibility
module ActiveSupport
  def self.on_load(name, &block)
    # No-op for testing
  end
end

# Mock I18n for Rails
module I18n
  def self.t(key, options = {})
    key.to_s.split(".").last.humanize
  end
end

# Mock ActionCable for WebSocket support
module ActionCable
  MockServer = Struct.new(:mount)

  def self.server
    MockServer.new
  end
end

# Mock RAAF modules that might be missing
module RAAF
  module Memory
    VERSION = "0.1.0"
  end

  module Tracing
    VERSION = "0.1.0"

    MockTracer = Struct.new(:add_processor)

    def self.create_tracer
      # Mock tracer
      MockTracer.new
    end
  end
end

# Add Rails Object extensions
class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def present?
    !blank?
  end
end

class NilClass
  def blank?
    true
  end
end

class String
  def blank?
    strip.empty?
  end

  def humanize
    gsub("_", " ").capitalize
  end

  def html_safe
    self
  end
end

class Array
  def blank?
    empty?
  end
end

class Hash
  def blank?
    empty?
  end
end

# Now require our gem
require "raaf-rails"

# Require RSpec
require "rspec"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure output formatting
  config.default_formatter = "doc" if config.files_to_run.one?

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Allow focusing on specific tests
  config.filter_run_when_matching :focus
end
