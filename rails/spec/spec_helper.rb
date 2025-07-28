# frozen_string_literal: true

require "bundler/setup"
require "time"
require "securerandom"
require "json"
require "set"

# Add parent gems to load path if in development
parent_dir = File.expand_path("../..", __dir__)
core_lib = File.join(parent_dir, "core/lib")
memory_lib = File.join(parent_dir, "memory/lib")
tracing_lib = File.join(parent_dir, "tracing/lib")

$LOAD_PATH.unshift(core_lib) if File.directory?(core_lib)
$LOAD_PATH.unshift(memory_lib) if File.directory?(memory_lib)
$LOAD_PATH.unshift(tracing_lib) if File.directory?(tracing_lib)

# Require core gems first
require "raaf-core"
require "raaf-memory"
require "raaf-tracing"

# Require testing support
require "raaf-testing"
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

    def self.isolated_namespace
      RAAF::Rails
    end

    MockConfig = Struct.new(:generators, :assets, :autoload_paths, :eager_load_paths, :after_initialize, :to_prepare, :i18n)
    MockGenerators = Struct.new(:test_framework)
    MockAssets = Struct.new(:enabled, :paths, :precompile)
    MockI18n = Struct.new(:load_path)

    def self.config
      @config ||= MockConfig.new(
        MockGenerators.new(:rspec),
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
    MockAppConfig = Struct.new(:root, :assets, :middleware)
    MockMiddleware = Struct.new(:use)

    def self.config
      @config ||= MockAppConfig.new(
        Pathname.new(Dir.pwd),
        Engine::MockAssets.new(true, [], []),
        MockMiddleware.new(->(klass) {})
      )
    end

    # rubocop:disable Rails/Delegate
    # Can't use delegate without ActiveSupport in test environment
    def config
      self.class.config
    end
    # rubocop:enable Rails/Delegate

    def self.routes
      @routes ||= Engine::MockRoutes.new(->(&block) {})
    end

    # rubocop:disable Rails/Delegate
    def routes
      self.class.routes
    end
    # rubocop:enable Rails/Delegate

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

    # Instance methods for controllers
    def params
      @params ||= {}
    end

    def respond_to(&block)
      # No-op for testing
    end

    def render(*args)
      # No-op for testing
    end

    def redirect_to(*args)
      # No-op for testing
    end

    def redirect_back(*args)
      # No-op for testing
    end

    def flash
      @flash ||= {}
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

    def self.count
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

    def self.not(*args)
      self
    end

    def self.sort_by(&block)
      []
    end

    def self.first(*args)
      []
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

  class SafeBuffer < String
    def html_safe
      self
    end
  end
end

# Mock Time.zone for Rails
class Time
  MockZone = Struct.new(:parse)

  def self.zone
    @zone ||= MockZone.new(->(str) { Time.parse(str) })
  end

  def self.current
    Time.now
  end
end

# Add Rails String extensions
class String
  def humanize
    gsub("_", " ").capitalize
  end

  def html_safe
    self
  end

  def blank?
    strip.empty?
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

# Add Rails NilClass extensions
class NilClass
  def blank?
    true
  end
end

# Add Rails Array extensions
class Array
  def blank?
    empty?
  end
end

# Add Rails Hash extensions
class Hash
  def blank?
    empty?
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

# Mock RAAF Rails models before requiring the gem
module RAAF
  module Rails
    class AgentModel < ::ActiveRecord::Base
      def self.table_name
        "agents"
      end

      def total_conversations
        42
      end

      def success_rate
        95.5
      end

      def avg_response_time
        1.234
      end

      def self.new(attrs = {})
        instance = super()
        attrs.each do |key, value|
          instance.send("#{key}=", value) if instance.respond_to?("#{key}=")
        end
        instance
      end
    end

    class ConversationModel < ::ActiveRecord::Base
      def self.table_name
        "conversations"
      end

      def self.messages
        MessageModel
      end
    end

    class MessageModel < ::ActiveRecord::Base
      def self.table_name
        "messages"
      end
    end
  end
end

# Now require our gem
require "raaf-rails"

# Add test helper methods
module TestHelpers
  def content_tag(name, content = nil, options = nil, &block)
    content = block.call if block_given?
    attrs = options ? options.map { |k, v| " #{k}=\"#{v}\"" }.join : ""
    "<#{name}#{attrs}>#{content}</#{name}>"
  end

  def tag(name, options = nil)
    attrs = options ? options.map { |k, v| " #{k}=\"#{v}\"" }.join : ""
    "<#{name}#{attrs} />"
  end

  def link_to(text, url, options = {})
    content_tag(:a, text, options.merge(href: url))
  end

  def safe_join(array, sep = "")
    array.join(sep)
  end

  # Path helpers
  def login_path
    "/login"
  end

  def root_path
    "/"
  end
end

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.include TestHelpers
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

  # Configure shared context and examples
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Include testing matchers
  config.include RAAF::Testing::Matchers

  # Set up temporary directories for file-based tests
  config.around(:each, :with_temp_files) do |example|
    Dir.mktmpdir("raaf_rails_test") do |temp_dir|
      @temp_dir = temp_dir
      example.run
    end
  ensure
    @temp_dir = nil
  end

  # Capture stdout/stderr for testing output
  config.around(:each, :capture_output) do |example|
    original_stdout = $stdout
    original_stderr = $stderr

    stdout_capture = StringIO.new
    stderr_capture = StringIO.new

    $stdout = stdout_capture
    $stderr = stderr_capture

    begin
      example.run
    ensure
      # Store captured output in example metadata
      example.metadata[:stdout] = stdout_capture.string
      example.metadata[:stderr] = stderr_capture.string

      $stdout = original_stdout
      $stderr = original_stderr
    end
  end
end

# Helper methods to access captured output
def captured_stdout
  RSpec.current_example.metadata[:stdout]
end

def captured_stderr
  RSpec.current_example.metadata[:stderr]
end

# Helper method to access temp directory
def temp_dir
  @temp_dir ||= Dir.mktmpdir
end

# Helper method to silence warnings
def silence_warnings
  original_verbosity = $VERBOSE
  $VERBOSE = nil
  yield
ensure
  $VERBOSE = original_verbosity
end
