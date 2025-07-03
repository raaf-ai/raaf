# frozen_string_literal: true

namespace :debug do
  desc "Show current debug configuration"
  task config: :environment do
    puts "🔧 Debug Configuration".colorize(:blue)
    puts "=" * 50
    puts "DEBUG: #{OpenAIAgents::DebugUtils.enabled?}".colorize(:green)
    puts "DEBUG_LEVEL: #{OpenAIAgents::DebugUtils.level}".colorize(:green)
    puts "DEBUG_OUTPUT: #{OpenAIAgents::DebugUtils.output_target}".colorize(:green)
    puts
    puts "AI-specific debugging:".colorize(:yellow)
    puts "  AI_DEBUG: #{OpenAIAgents::DebugUtils.ai_debug_enabled?}".colorize(:green)
    puts "  TRACE_DEBUG: #{OpenAIAgents::DebugUtils.trace_debug_enabled?}".colorize(:green)
    puts "  RAW_DEBUG: #{OpenAIAgents::DebugUtils.raw_debug_enabled?}".colorize(:green)
    puts
    puts "OpenAI Agents specific:".colorize(:yellow)
    puts "  TRACING_ENABLED: #{OpenAIAgents::DebugUtils.tracing_enabled?}".colorize(:green)
    puts "  CONVERSATION_DEBUG: #{OpenAIAgents::DebugUtils.conversation_debug_enabled?}".colorize(:green)
    puts
    puts "Environment Variables:".colorize(:yellow)
    debug_vars = ENV.select { |k, _| k.include?('DEBUG') || k.include?('TRACE') || k.include?('OPENAI') }
    debug_vars.each { |k, v| puts "  #{k}: #{v}".colorize(:green) }
  end

  desc "Test debug logging at all levels"
  task test_logging: :environment do
    puts "🧪 Testing Debug Logging".colorize(:blue)
    puts "=" * 50
    
    %w[debug info warn error fatal].each do |level|
      OpenAIAgents::DebugUtils.log(level.to_sym, "Test #{level} message", context: { test: true })
    end
    
    puts "\nTesting AI-specific logging:".colorize(:yellow)
    OpenAIAgents::DebugUtils.ai_log("Test AI debug message", context: { agent: "test" })
    OpenAIAgents::DebugUtils.trace_log("Test trace message", context: { action: "test" })
    OpenAIAgents::DebugUtils.raw_log("Test raw debug message", context: { response: "test" })
  end

  desc "Test existing debugging system integration"
  task test_existing_debugging: :environment do
    puts "🔧 Testing Integration with Existing Debugging System".colorize(:blue)
    puts "=" * 50
    
    # Test if existing debugging classes are available
    if defined?(OpenAIAgents::Debugging::Debugger)
      puts "✅ OpenAIAgents::Debugging::Debugger available".colorize(:green)
      
      debugger = OpenAIAgents::Debugging::Debugger.new
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
    
    if OpenAIAgents::DebugUtils.tracing_enabled?
      puts "✅ Tracing is enabled".colorize(:green)
      
      # Test trace logging
      OpenAIAgents::DebugUtils.trace_log("Test trace entry", context: {
        operation: "test",
        timestamp: Time.current,
        trace_id: SecureRandom.uuid
      })
    else
      puts "⚠️  Tracing is disabled".colorize(:yellow)
      puts "Enable with TRACE_DEBUG=true or OPENAI_AGENTS_TRACE_DEBUG=true"
    end
  end

  desc "Benchmark debug utilities performance"
  task benchmark: :environment do
    puts "⏱️  Benchmarking Debug Utilities".colorize(:blue)
    puts "=" * 50
    
    result = OpenAIAgents::DebugUtils.benchmark("test_operation") do
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
      Rake::Task['openai_agents:tracing:token_stats'].invoke
    rescue StandardError
      puts "ℹ️  Tracing stats not available or tracing not configured".colorize(:yellow)
      puts "Enable tracing to see statistics"
    end
  end

  desc "Clear debug logs"
  task clear_logs: :environment do
    debug_log = File.join(Dir.pwd, 'log', 'debug.log')
    
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
    puts "DEBUG=true"
    puts "DEBUG_LEVEL=debug"
    puts "DEBUG_OUTPUT=both"
    puts "AI_DEBUG=true"
    puts "TRACE_DEBUG=true"
    puts "RAW_DEBUG=true"
    puts "OPENAI_AGENTS_TRACE_DEBUG=true"
    puts "OPENAI_AGENTS_DEBUG_CONVERSATION=true"
    puts "OPENAI_AGENTS_DEBUG_RAW=true"
  end

  desc "Run comprehensive debug test suite"
  task test_all: [:config, :test_logging, :test_existing_debugging, :test_tracing, :benchmark] do
    puts "\n✅ All debug tests completed!".colorize(:green)
  end
end