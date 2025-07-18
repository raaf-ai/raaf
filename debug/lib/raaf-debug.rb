# frozen_string_literal: true

require_relative "raaf/debug/version"
require_relative "raaf/debug/tracer"
require_relative "raaf/debug/profiler"
require_relative "raaf/debug/inspector"
require_relative "raaf/debug/debugger"
require_relative "raaf/debug/log_analyzer"
require_relative "raaf/debug/performance_monitor"
require_relative "raaf/debug/memory_tracker"
require_relative "raaf/debug/request_recorder"
require_relative "raaf/debug/interactive_console"
require_relative "raaf/debug/formatter"
require_relative "raaf/debug/middleware"

module RAAF
  ##
  # Advanced debugging and development utilities for Ruby AI Agents Factory
  #
  # The Debug module provides comprehensive debugging tools including request tracing,
  # performance profiling, interactive debugging, log analysis, and development utilities
  # for AI agents. It enables developers to deeply inspect agent behavior, analyze
  # performance bottlenecks, and debug issues in development and production environments.
  #
  # Key features:
  # - **Request Tracing** - Detailed tracing of agent requests and responses
  # - **Performance Profiling** - CPU, memory, and execution profiling
  # - **Interactive Debugging** - REPL-based debugging with breakpoints
  # - **Log Analysis** - Automated log parsing and analysis
  # - **Performance Monitoring** - Real-time performance metrics
  # - **Memory Tracking** - Memory usage analysis and leak detection
  # - **Request Recording** - Record and replay agent interactions
  # - **Interactive Console** - Live debugging console for agents
  # - **Formatted Output** - Rich terminal output with colors and tables
  # - **Debug Middleware** - Plug-in debugging for agent pipelines
  #
  # @example Basic debugging setup
  #   require 'raaf-debug'
  #   
  #   # Enable debug mode
  #   RAAF::Debug.enable!
  #   
  #   # Create debug-enabled agent
  #   agent = RAAF::Agent.new(
  #     name: "DebugAgent",
  #     instructions: "You are a helpful assistant",
  #     debug: true
  #   )
  #   
  #   # Run with debugging
  #   result = agent.run("Hello") do |debug_info|
  #     puts "Debug: #{debug_info}"
  #   end
  #
  # @example Request tracing
  #   require 'raaf-debug'
  #   
  #   # Create tracer
  #   tracer = RAAF::Debug::Tracer.new
  #   
  #   # Enable tracing
  #   tracer.start
  #   
  #   # Trace agent execution
  #   tracer.trace_agent_execution(agent, "Hello world") do |trace|
  #     puts "Request: #{trace.request}"
  #     puts "Response: #{trace.response}"
  #     puts "Duration: #{trace.duration}ms"
  #   end
  #
  # @example Performance profiling
  #   require 'raaf-debug'
  #   
  #   # Create profiler
  #   profiler = RAAF::Debug::Profiler.new
  #   
  #   # Profile agent execution
  #   profile_result = profiler.profile do
  #     100.times { agent.run("Test message") }
  #   end
  #   
  #   # Generate profile report
  #   report = profiler.generate_report(profile_result)
  #   puts report
  #
  # @example Interactive debugging
  #   require 'raaf-debug'
  #   
  #   # Create debugger
  #   debugger = RAAF::Debug::Debugger.new
  #   
  #   # Set breakpoint
  #   debugger.set_breakpoint(agent, :before_run) do |context|
  #     puts "About to run agent with: #{context.message}"
  #     # Interactive debugging session
  #     binding.pry
  #   end
  #   
  #   # Run agent with debugging
  #   agent.run("Debug this message")
  #
  # @example Log analysis
  #   require 'raaf-debug'
  #   
  #   # Create log analyzer
  #   analyzer = RAAF::Debug::LogAnalyzer.new
  #   
  #   # Analyze log files
  #   analysis = analyzer.analyze_log_file("logs/agent.log")
  #   
  #   # Get insights
  #   puts "Error rate: #{analysis.error_rate}%"
  #   puts "Average response time: #{analysis.avg_response_time}ms"
  #   puts "Most common errors: #{analysis.top_errors}"
  #
  # @example Memory tracking
  #   require 'raaf-debug'
  #   
  #   # Create memory tracker
  #   tracker = RAAF::Debug::MemoryTracker.new
  #   
  #   # Track memory usage
  #   tracker.start_tracking
  #   
  #   # Run agent operations
  #   100.times { agent.run("Memory test") }
  #   
  #   # Get memory report
  #   report = tracker.generate_report
  #   puts "Memory used: #{report.memory_used}MB"
  #   puts "Potential leaks: #{report.potential_leaks}"
  #
  # @since 1.0.0
  module Debug
    # Default configuration
    DEFAULT_CONFIG = {
      # General debug settings
      enabled: false,
      log_level: :debug,
      output_format: :terminal,
      color_output: true,
      
      # Tracer settings
      tracer: {
        enabled: true,
        trace_requests: true,
        trace_responses: true,
        trace_internal_calls: false,
        max_trace_depth: 10,
        include_stack_trace: true
      },
      
      # Profiler settings
      profiler: {
        enabled: true,
        cpu_profiling: true,
        memory_profiling: true,
        allocation_tracking: true,
        profile_threshold: 0.01,
        max_samples: 10000
      },
      
      # Inspector settings
      inspector: {
        enabled: true,
        inspect_requests: true,
        inspect_responses: true,
        inspect_internal_state: true,
        max_inspection_depth: 5
      },
      
      # Debugger settings
      debugger: {
        enabled: true,
        interactive_mode: true,
        breakpoints_enabled: true,
        auto_continue: false,
        debug_console: true
      },
      
      # Log analyzer settings
      log_analyzer: {
        enabled: true,
        real_time_analysis: true,
        pattern_detection: true,
        error_categorization: true,
        performance_analysis: true
      },
      
      # Performance monitor settings
      performance_monitor: {
        enabled: true,
        real_time_monitoring: true,
        alerting_enabled: true,
        metrics_collection: true,
        dashboard_enabled: true
      },
      
      # Memory tracker settings
      memory_tracker: {
        enabled: true,
        track_allocations: true,
        leak_detection: true,
        gc_analysis: true,
        memory_snapshots: true
      },
      
      # Request recorder settings
      request_recorder: {
        enabled: true,
        record_requests: true,
        record_responses: true,
        record_metadata: true,
        replay_enabled: true
      },
      
      # Interactive console settings
      interactive_console: {
        enabled: true,
        auto_start: false,
        command_history: true,
        syntax_highlighting: true,
        code_completion: true
      },
      
      # Formatter settings
      formatter: {
        enabled: true,
        terminal_colors: true,
        table_formatting: true,
        json_pretty_print: true,
        markdown_output: false
      },
      
      # Middleware settings
      middleware: {
        enabled: true,
        auto_inject: true,
        performance_tracking: true,
        error_handling: true,
        request_logging: true
      }
    }.freeze

    class << self
      # @return [Hash] Current configuration
      attr_accessor :config

      # @return [Boolean] Debug enabled status
      attr_accessor :enabled

      ##
      # Configure debug settings
      #
      # @param options [Hash] Configuration options
      # @yield [config] Configuration block
      #
      # @example Configure debug
      #   RAAF::Debug.configure do |config|
      #     config.enabled = true
      #     config.tracer.trace_internal_calls = true
      #     config.profiler.cpu_profiling = true
      #   end
      #
      def configure
        @config ||= deep_dup(DEFAULT_CONFIG)
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= deep_dup(DEFAULT_CONFIG)
      end

      ##
      # Enable debug mode
      #
      # @param options [Hash] Enable options
      def enable!(options = {})
        @enabled = true
        @config ||= deep_dup(DEFAULT_CONFIG)
        @config.merge!(options)
        
        setup_debug_environment
        
        puts "🐛 Debug mode enabled".colorize(:green) if @config[:color_output]
      end

      ##
      # Disable debug mode
      #
      def disable!
        @enabled = false
        cleanup_debug_environment
        
        puts "🐛 Debug mode disabled".colorize(:red) if @config[:color_output]
      end

      ##
      # Check if debug mode is enabled
      #
      # @return [Boolean] True if debug mode is enabled
      def enabled?
        @enabled || false
      end

      ##
      # Create tracer
      #
      # @param options [Hash] Tracer options
      # @return [Tracer] Tracer instance
      def create_tracer(**options)
        Tracer.new(**config[:tracer].merge(options))
      end

      ##
      # Create profiler
      #
      # @param options [Hash] Profiler options
      # @return [Profiler] Profiler instance
      def create_profiler(**options)
        Profiler.new(**config[:profiler].merge(options))
      end

      ##
      # Create inspector
      #
      # @param options [Hash] Inspector options
      # @return [Inspector] Inspector instance
      def create_inspector(**options)
        Inspector.new(**config[:inspector].merge(options))
      end

      ##
      # Create debugger
      #
      # @param options [Hash] Debugger options
      # @return [Debugger] Debugger instance
      def create_debugger(**options)
        Debugger.new(**config[:debugger].merge(options))
      end

      ##
      # Create log analyzer
      #
      # @param options [Hash] Log analyzer options
      # @return [LogAnalyzer] Log analyzer instance
      def create_log_analyzer(**options)
        LogAnalyzer.new(**config[:log_analyzer].merge(options))
      end

      ##
      # Create performance monitor
      #
      # @param options [Hash] Performance monitor options
      # @return [PerformanceMonitor] Performance monitor instance
      def create_performance_monitor(**options)
        PerformanceMonitor.new(**config[:performance_monitor].merge(options))
      end

      ##
      # Create memory tracker
      #
      # @param options [Hash] Memory tracker options
      # @return [MemoryTracker] Memory tracker instance
      def create_memory_tracker(**options)
        MemoryTracker.new(**config[:memory_tracker].merge(options))
      end

      ##
      # Create request recorder
      #
      # @param options [Hash] Request recorder options
      # @return [RequestRecorder] Request recorder instance
      def create_request_recorder(**options)
        RequestRecorder.new(**config[:request_recorder].merge(options))
      end

      ##
      # Create interactive console
      #
      # @param options [Hash] Interactive console options
      # @return [InteractiveConsole] Interactive console instance
      def create_interactive_console(**options)
        InteractiveConsole.new(**config[:interactive_console].merge(options))
      end

      ##
      # Create formatter
      #
      # @param options [Hash] Formatter options
      # @return [Formatter] Formatter instance
      def create_formatter(**options)
        Formatter.new(**config[:formatter].merge(options))
      end

      ##
      # Create debug middleware
      #
      # @param options [Hash] Middleware options
      # @return [Middleware] Debug middleware instance
      def create_middleware(**options)
        Middleware.new(**config[:middleware].merge(options))
      end

      ##
      # Enable debug for an agent
      #
      # @param agent [Agent] Agent to debug
      # @param options [Hash] Debug options
      # @return [Agent] Agent with debug enabled
      def enable_debug(agent, **options)
        # Add debug middleware to agent
        middleware = create_middleware(**options)
        agent.add_middleware(middleware)
        
        # Set debug flag on agent
        agent.instance_variable_set(:@debug_enabled, true)
        
        agent
      end

      ##
      # Start debug session
      #
      # @param agent [Agent] Agent to debug
      # @param options [Hash] Session options
      # @return [DebugSession] Debug session instance
      def start_debug_session(agent, **options)
        DebugSession.new(agent: agent, **options)
      end

      ##
      # Quick debug helper
      #
      # @param agent [Agent] Agent to debug
      # @param message [String] Message to debug
      # @param options [Hash] Debug options
      # @yield [debug_info] Debug information
      def debug(agent, message, **options)
        return agent.run(message) unless enabled?
        
        tracer = create_tracer(**options)
        profiler = create_profiler(**options)
        
        debug_info = {}
        
        # Profile execution
        profile_result = profiler.profile do
          tracer.trace_agent_execution(agent, message) do |trace|
            debug_info[:trace] = trace
            yield debug_info if block_given?
          end
        end
        
        debug_info[:profile] = profile_result
        debug_info
      end

      ##
      # Get debug statistics
      #
      # @return [Hash] Debug statistics
      def statistics
        {
          enabled: enabled?,
          active_tracers: Tracer.active_count,
          active_profilers: Profiler.active_count,
          active_debuggers: Debugger.active_count,
          memory_usage: MemoryTracker.current_usage,
          performance_metrics: PerformanceMonitor.current_metrics
        }
      end

      ##
      # Generate debug report
      #
      # @param format [Symbol] Report format (:text, :json, :html)
      # @return [String] Debug report
      def generate_report(format: :text)
        formatter = create_formatter
        
        case format
        when :text
          formatter.format_debug_report(statistics)
        when :json
          JSON.pretty_generate(statistics)
        when :html
          formatter.format_html_report(statistics)
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      ##
      # Start interactive debug console
      #
      # @param agent [Agent] Agent to debug
      # @param options [Hash] Console options
      def start_console(agent = nil, **options)
        console = create_interactive_console(**options)
        console.start(agent)
      end

      ##
      # Debug breakpoint helper
      #
      # @param message [String] Breakpoint message
      # @param context [Hash] Debug context
      def breakpoint(message = "Debug breakpoint", context = {})
        return unless enabled?
        
        puts "🔍 #{message}".colorize(:yellow) if config[:color_output]
        puts "Context: #{context.inspect}" if context.any?
        
        if config[:debugger][:interactive_mode]
          binding.pry
        else
          puts "Interactive mode disabled. Set config.debugger.interactive_mode = true to enable."
        end
      end

      ##
      # Log debug message
      #
      # @param message [String] Debug message
      # @param level [Symbol] Log level
      # @param context [Hash] Debug context
      def log(message, level: :debug, **context)
        return unless enabled?
        
        formatted_message = create_formatter.format_log_message(message, level, context)
        puts formatted_message
      end

      ##
      # Measure execution time
      #
      # @param label [String] Measurement label
      # @yield Block to measure
      # @return [Object] Block result
      def measure(label = "Execution")
        return yield unless enabled?
        
        start_time = Time.current
        result = yield
        end_time = Time.current
        
        duration = ((end_time - start_time) * 1000).round(2)
        puts "⏱️  #{label}: #{duration}ms".colorize(:blue) if config[:color_output]
        
        result
      end

      ##
      # Memory snapshot
      #
      # @param label [String] Snapshot label
      # @return [Hash] Memory snapshot
      def memory_snapshot(label = "Memory snapshot")
        return {} unless enabled?
        
        tracker = create_memory_tracker
        snapshot = tracker.take_snapshot
        
        puts "📸 #{label}: #{snapshot[:memory_usage]}MB".colorize(:cyan) if config[:color_output]
        snapshot
      end

      private

      def deep_dup(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key] = value.is_a?(Hash) ? deep_dup(value) : value.dup
        end
      rescue TypeError
        hash
      end

      def setup_debug_environment
        # Set up debug environment
        require 'pry'
        require 'pry-byebug'
        
        # Configure Pry
        Pry.config.theme = "monokai"
        Pry.config.editor = ENV['EDITOR'] || 'vim'
        
        # Set up signal handlers
        setup_signal_handlers
      end

      def cleanup_debug_environment
        # Clean up debug environment
        # Remove signal handlers, close debug sessions, etc.
      end

      def setup_signal_handlers
        # Set up signal handlers for debugging
        Signal.trap('USR1') do
          puts "\n🐛 Debug signal received - starting debug console"
          start_console
        end

        Signal.trap('USR2') do
          puts "\n📊 Debug statistics:"
          puts generate_report
        end
      end
    end

    ##
    # Debug session for coordinated debugging
    #
    class DebugSession
      include RAAF::Logging

      attr_reader :agent, :tracer, :profiler, :debugger, :session_id

      def initialize(agent:, **options)
        @agent = agent
        @session_id = SecureRandom.hex(8)
        @options = options
        @tracer = Debug.create_tracer(**options)
        @profiler = Debug.create_profiler(**options)
        @debugger = Debug.create_debugger(**options)
        @active = false
      end

      def start
        @active = true
        @tracer.start
        @profiler.start
        @debugger.start
        
        log_info("Debug session started", session_id: @session_id)
        self
      end

      def stop
        @active = false
        @tracer.stop
        @profiler.stop
        @debugger.stop
        
        log_info("Debug session stopped", session_id: @session_id)
        self
      end

      def debug_run(message, **options)
        return @agent.run(message) unless @active
        
        debug_info = {
          session_id: @session_id,
          message: message,
          options: options
        }
        
        @profiler.profile do
          @tracer.trace_agent_execution(@agent, message) do |trace|
            debug_info[:trace] = trace
            yield debug_info if block_given?
          end
        end
      end

      def set_breakpoint(event, &block)
        @debugger.set_breakpoint(@agent, event, &block)
      end

      def active?
        @active
      end

      def statistics
        {
          session_id: @session_id,
          active: @active,
          agent: @agent.name,
          tracer_stats: @tracer.statistics,
          profiler_stats: @profiler.statistics,
          debugger_stats: @debugger.statistics
        }
      end
    end
  end
end