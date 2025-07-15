# frozen_string_literal: true

require_relative "../openai_agents"

namespace :debug do
  desc "Show current debug configuration"
  task config: :environment do
    config = OpenAIAgents::Logging.configuration

    puts "🔧 Debug Configuration".colorize(:blue)
    puts "=" * 50
    puts "LOG_LEVEL: #{config.log_level}".colorize(:green)
    puts "LOG_FORMAT: #{config.log_format}".colorize(:green)
    puts "LOG_OUTPUT: #{config.log_output}".colorize(:green)
    puts "LOG_FILE: #{config.log_file}".colorize(:green)
    puts
    puts "Debug Categories:".colorize(:yellow)
    puts "  Available: tracing, api, tools, handoff, context, http, general".colorize(:cyan)
    puts "  Enabled: #{config.debug_categories.join(", ")}".colorize(:green)
    puts
    puts "Environment Variables:".colorize(:yellow)
    debug_vars = ENV.select do |k, _|
      k.include?("LOG") || k.include?("DEBUG") || k.include?("TRACE") || k.include?("OPENAI")
    end
    debug_vars.each { |k, v| puts "  #{k}: #{v}".colorize(:green) }
  end

  desc "Test debug logging at all levels"
  task test_logging: :environment do
    puts "🧪 Testing Debug Logging".colorize(:blue)
    puts "=" * 50

    %w[debug info warn error fatal].each do |level|
      OpenAIAgents::Logging.send(level, "Test #{level} message", test: true)
    end

    puts "\nTesting category-specific logging:".colorize(:yellow)
    OpenAIAgents::Logging.debug("Test API debug message", category: :api, agent: "test")
    OpenAIAgents::Logging.debug("Test trace message", category: :tracing, action: "test")
    OpenAIAgents::Logging.debug("Test tools message", category: :tools, tool: "test")
    OpenAIAgents::Logging.debug("Test handoff message", category: :handoff, from: "agent1", to: "agent2")
  end

  desc "Test existing debugging system integration"
  task test_existing_debugging: :environment do
    puts "🔧 Testing Integration with Existing Debugging System".colorize(:blue)
    puts "=" * 50

    # Test if existing debugging classes are available
    if defined?(OpenAIAgents::Debugging::Debugger)
      puts "✅ OpenAIAgents::Debugging::Debugger available".colorize(:green)

      OpenAIAgents::Debugging::Debugger.new
      puts "Debugger instance created".colorize(:green)
    else
      puts "⚠️  OpenAIAgents::Debugging::Debugger not loaded".colorize(:yellow)
    end

    # Test tracing system
    if defined?(OpenAIAgents::Tracing)
      puts "✅ OpenAIAgents::Tracing available".colorize(:green)
    else
      puts "⚠️  OpenAIAgents::Tracing not loaded".colorize(:yellow)
    end
  end

  desc "Test tracing configuration"
  task test_tracing: :environment do
    puts "📊 Testing Tracing Configuration".colorize(:blue)
    puts "=" * 50

    config = OpenAIAgents::Logging.configuration
    if config.debug_enabled?(:tracing)
      puts "✅ Tracing debug is enabled".colorize(:green)

      # Test trace logging
      OpenAIAgents::Logging.debug("Test trace entry", category: :tracing,
                                                      operation: "test",
                                                      timestamp: Time.current,
                                                      trace_id: SecureRandom.uuid)
    else
      puts "⚠️  Tracing debug is disabled".colorize(:yellow)
      puts "Enable with OPENAI_AGENTS_DEBUG_CATEGORIES=tracing (or all)"
    end
  end

  desc "Test handoff debugging"
  task test_handoff: :environment do
    puts "🤝 Testing Handoff Debug Configuration".colorize(:blue)
    puts "=" * 50

    config = OpenAIAgents::Logging.configuration
    if config.debug_enabled?(:handoff)
      puts "✅ Handoff debug is enabled".colorize(:green)

      # Test handoff logging
      OpenAIAgents::Logging.debug("Test handoff entry", category: :handoff,
                                                        from_agent: "AgentA",
                                                        to_agent: "AgentB",
                                                        method: "test")
      puts "\nHandoff debug messages will show:".colorize(:cyan)
      puts "  • Handoff detection (text/JSON patterns)"
      puts "  • Agent lookup and validation"
      puts "  • Handoff execution flow"
      puts "  • Available handoffs in prompts"
      puts "  • Custom handoff function calls"
    else
      puts "⚠️  Handoff debug is disabled".colorize(:yellow)
      puts "Enable with OPENAI_AGENTS_DEBUG_CATEGORIES=handoff (or all)"
    end
  end

  desc "Benchmark logging system performance"
  task benchmark: :environment do
    puts "⏱️  Benchmarking Logging System".colorize(:blue)
    puts "=" * 50

    result = OpenAIAgents::Logging.benchmark("test_operation") do
      sleep(0.1)
      "Operation completed"
    end

    puts "Result: #{result}".colorize(:green)
  end

  desc "Show tracing stats (if available)"
  task tracing_stats: :environment do
    puts "📈 Tracing Statistics".colorize(:blue)
    puts "=" * 50

    begin
      # Check if tracing tasks exist
      Rake::Task["openai_agents:tracing:token_stats"].invoke
    rescue StandardError
      puts "ℹ️  Tracing stats not available or tracing not configured".colorize(:yellow)
      puts "Enable tracing to see statistics"
    end
  end

  desc "Clear debug logs"
  task clear_logs: :environment do
    debug_log = File.join(Dir.pwd, "log", "debug.log")

    if File.exist?(debug_log)
      File.delete(debug_log)
      puts "🗑️  Debug log cleared".colorize(:green)
    else
      puts "ℹ️  No debug log found".colorize(:yellow)
    end
  end

  desc "Enable all debugging"
  task enable_all: :environment do
    puts "🔛 Enabling all debugging features".colorize(:blue)
    puts "Add these to your environment:".colorize(:yellow)
    puts
    puts "OPENAI_AGENTS_LOG_LEVEL=debug"
    puts "OPENAI_AGENTS_LOG_FORMAT=text"
    puts "OPENAI_AGENTS_LOG_OUTPUT=console"
    puts "OPENAI_AGENTS_DEBUG_CATEGORIES=all"
    puts
    puts "For specific categories only:".colorize(:cyan)
    puts "OPENAI_AGENTS_DEBUG_CATEGORIES=tracing,api,tools,http"
  end

  desc "Run comprehensive debug test suite"
  task test_all: %i[config test_logging test_existing_debugging test_tracing test_handoff benchmark] do
    puts "\n✅ All debug tests completed!".colorize(:green)
  end
end
