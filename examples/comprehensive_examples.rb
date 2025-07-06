#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive Examples for OpenAI Agents Ruby
# This file demonstrates all major features with practical examples

require_relative '../lib/openai_agents'
require 'json'
require 'fileutils'

# Set up API key
ENV['OPENAI_API_KEY'] ||= 'your-api-key-here'

class ComprehensiveExamples
  def self.run_all
    new.run_all_examples
  end

  def run_all_examples
    puts "=== OpenAI Agents Ruby - Comprehensive Examples ==="
    puts

    # Run each example category
    basic_examples
    memory_examples
    vector_search_examples
    document_generation_examples
    guardrails_examples
    debugging_examples
    compliance_examples
    multi_provider_examples
    streaming_examples
    advanced_tools_examples
    
    puts "\n=== All examples completed! ==="
  end

  private

  def basic_examples
    section "Basic Agent Usage" do
      # Simple agent with tool
      def calculator(expression)
        eval(expression).to_s
      rescue => e
        "Error: #{e.message}"
      end

      agent = OpenAIAgents::Agent.new(
        name: "Calculator",
        instructions: "You are a helpful math assistant. Use the calculator tool for computations.",
        model: "gpt-4o"
      )
      
      agent.add_tool(method(:calculator))
      
      runner = OpenAIAgents::Runner.new(agent: agent)
      result = runner.run("What is 25 * 4 + 10?")
      
      puts "Calculator result: #{result.messages.last[:content]}"
    end
  end

  def memory_examples
    section "Memory Management" do
      # Token-aware memory
      memory_store = OpenAIAgents::Memory::InMemoryStore.new
      memory_manager = OpenAIAgents::Memory::MemoryManager.new(
        store: memory_store,
        token_limit: 2000,
        pruning_strategy: :sliding_window
      )
      
      agent = OpenAIAgents::Agent.new(
        name: "MemoryAssistant",
        instructions: "You are a helpful assistant with memory of our conversations.",
        model: "gpt-4o"
      )
      
      runner = OpenAIAgents::Runner.new(
        agent: agent,
        memory_manager: memory_manager
      )
      
      # First interaction
      runner.run("My name is Alice and I work at TechCorp as a senior developer.")
      runner.run("I'm working on a Ruby on Rails project.")
      
      # Test memory recall
      result = runner.run("What do you remember about me?")
      puts "Memory recall: #{result.messages.last[:content]}"
      
      # Show memory stats
      puts "Memory stats: #{memory_manager.get_stats}"
    end
  end

  def vector_search_examples
    section "Vector Search & Semantic Search" do
      # Create in-memory vector store
      vector_store = OpenAIAgents::VectorStore.new(adapter: :in_memory)
      
      # Add technical documentation
      documents = [
        {
          content: "Ruby on Rails is a web application framework written in Ruby. It follows MVC architecture.",
          metadata: { topic: "frameworks", language: "ruby", type: "web" }
        },
        {
          content: "Django is a high-level Python web framework that encourages rapid development.",
          metadata: { topic: "frameworks", language: "python", type: "web" }
        },
        {
          content: "React is a JavaScript library for building user interfaces, particularly single-page applications.",
          metadata: { topic: "libraries", language: "javascript", type: "frontend" }
        },
        {
          content: "PostgreSQL is a powerful, open source object-relational database system.",
          metadata: { topic: "databases", type: "sql", category: "storage" }
        }
      ]
      
      vector_store.add_documents(documents)
      
      # Create agent with vector search
      agent = OpenAIAgents::Agent.new(
        name: "TechExpert",
        instructions: "You are a technical expert. Use vector search to find relevant information before answering.",
        model: "gpt-4o"
      )
      
      # Add vector search tool
      search_tool = OpenAIAgents::Tools::VectorSearchTool.new(
        vector_store: vector_store,
        num_results: 3,
        metadata_filter: nil
      )
      agent.add_tool(search_tool)
      
      runner = OpenAIAgents::Runner.new(agent: agent)
      
      # Test searches
      queries = [
        "What Ruby frameworks are available for web development?",
        "Tell me about JavaScript libraries for UI development",
        "What databases should I consider for my project?"
      ]
      
      queries.each do |query|
        result = runner.run(query)
        puts "\nQuery: #{query}"
        puts "Answer: #{result.messages.last[:content]}"
      end
    end
  end

  def document_generation_examples
    section "Document Generation" do
      # Create document generation agent
      agent = OpenAIAgents::Agent.new(
        name: "DocumentCreator",
        instructions: "You are a professional document creator. Generate well-formatted documents based on user requests.",
        model: "gpt-4o"
      )
      
      # Add document tools
      doc_tool = OpenAIAgents::Tools::DocumentTool.new(
        output_dir: "./generated_docs"
      )
      report_tool = OpenAIAgents::Tools::ReportTool.new(
        output_dir: "./generated_reports"
      )
      
      agent.add_tool(doc_tool)
      agent.add_tool(report_tool)
      
      runner = OpenAIAgents::Runner.new(agent: agent)
      
      # Generate different document types
      puts "Generating sample documents..."
      
      # PDF Invoice
      runner.run(<<~PROMPT)
        Create a PDF invoice for:
        - Client: Acme Corporation
        - Invoice #: INV-2024-001
        - Services: Ruby on Rails Development (40 hours @ $150/hour)
        - Due: Net 30
      PROMPT
      
      # Excel report
      runner.run(<<~PROMPT)
        Create an Excel spreadsheet with quarterly sales data:
        - Q1: Product A: $45,000, Product B: $32,000, Product C: $28,000
        - Q2: Product A: $52,000, Product B: $35,000, Product C: $31,000
        - Q3: Product A: $48,000, Product B: $38,000, Product C: $33,000
        - Q4: Product A: $55,000, Product B: $41,000, Product C: $36,000
        Include totals and a summary sheet.
      PROMPT
      
      puts "Documents generated in ./generated_docs/ and ./generated_reports/"
    end
  end

  def guardrails_examples
    section "Guardrails & Security" do
      # Configure multiple guardrails
      pii_guardrail = OpenAIAgents::Guardrails::PIIDetector.new(
        action: :redact,
        sensitivity: :high,
        redaction_placeholder: "[REDACTED]"
      )
      
      security_guardrail = OpenAIAgents::Guardrails::SecurityGuardrail.new(
        block_patterns: [
          /password\s*[:=]\s*\S+/i,
          /api[_-]?key\s*[:=]\s*\S+/i,
          /secret\s*[:=]\s*\S+/i
        ],
        action: :block
      )
      
      tripwire = OpenAIAgents::Guardrails::Tripwire.new(
        patterns: [/rm\s+-rf\s+\//, /drop\s+database/i],
        action: :terminate
      )
      
      # Use parallel guardrails for performance
      guardrails = OpenAIAgents::ParallelGuardrails.new([
        pii_guardrail,
        security_guardrail,
        tripwire
      ])
      
      agent = OpenAIAgents::Agent.new(
        name: "SecureAssistant",
        instructions: "You are a security-conscious assistant.",
        model: "gpt-4o",
        guardrails: guardrails
      )
      
      runner = OpenAIAgents::Runner.new(agent: agent)
      
      # Test guardrails
      test_inputs = [
        "My email is john@example.com and SSN is 123-45-6789",
        "Can you help me format this data?",
        "The API_KEY=secret123 should be stored securely"
      ]
      
      test_inputs.each do |input|
        puts "\nInput: #{input}"
        begin
          result = runner.run(input)
          puts "Output: #{result.messages.last[:content]}"
        rescue OpenAIAgents::GuardrailViolation => e
          puts "Blocked: #{e.message}"
        end
      end
    end
  end

  def debugging_examples
    section "Interactive Debugging" do
      # Create debugger
      debugger = OpenAIAgents::Debugging::Debugger.new(
        log_level: :debug,
        capture_snapshots: true,
        enable_profiling: true
      )
      
      # Create agent with tools for debugging demo
      def slow_operation(seconds)
        sleep(seconds.to_i)
        "Operation completed after #{seconds} seconds"
      end
      
      agent = OpenAIAgents::Agent.new(
        name: "DebugDemo",
        instructions: "You are an agent being debugged. Use tools when asked.",
        model: "gpt-4o"
      )
      
      agent.add_tool(method(:slow_operation))
      
      # Use debug runner
      runner = OpenAIAgents::DebugRunner.new(
        agent: agent,
        debugger: debugger
      )
      
      # Set breakpoints
      debugger.set_breakpoint(:before_tool_call)
      debugger.set_breakpoint(:after_response)
      
      # Watch variables
      debugger.watch(:messages)
      debugger.watch(:token_usage)
      
      puts "Running with debugger..."
      result = runner.run("Please run the slow operation for 2 seconds")
      
      # Show debug info
      puts "\nDebug Summary:"
      puts "- Breakpoints hit: #{debugger.breakpoints_hit}"
      puts "- Performance metrics: #{debugger.performance_metrics}"
      puts "- Token usage: #{debugger.watched_variables[:token_usage]}"
      
      # Export debug session
      debugger.export_session("debug_session.json")
      puts "Debug session exported to debug_session.json"
    end
  end

  def compliance_examples
    section "Compliance & Audit" do
      # Set up audit logger
      audit_logger = OpenAIAgents::Compliance::AuditLogger.new(
        storage_backend: :file,
        file_path: "./audit_logs.json",
        retention_days: 90
      )
      
      # Set up policy manager
      policy_manager = OpenAIAgents::Compliance::PolicyManager.new
      
      # Add data retention policy
      policy_manager.add_policy(
        name: "data_retention",
        type: :retention,
        rules: {
          personal_data: { retention_days: 90 },
          financial_data: { retention_days: 2555 }
        }
      )
      
      # Add PII handling policy  
      policy_manager.add_policy(
        name: "pii_handling",
        type: :data_handling,
        rules: {
          ssn: { action: :redact },
          email: { action: :hash },
          phone: { action: :mask, format: "XXX-XXX-####" }
        }
      )
      
      # Create compliance monitor
      compliance_monitor = OpenAIAgents::Compliance::ComplianceMonitor.new(
        frameworks: [:gdpr, :soc2],
        alert_thresholds: {
          pii_exposure_rate: 0.01,
          unauthorized_access: 0
        }
      )
      
      agent = OpenAIAgents::Agent.new(
        name: "ComplianceAgent",
        instructions: "You are a compliance-aware assistant.",
        model: "gpt-4o"
      )
      
      runner = OpenAIAgents::Runner.new(
        agent: agent,
        audit_logger: audit_logger,
        policy_manager: policy_manager,
        compliance_monitor: compliance_monitor
      )
      
      # Run some interactions
      runner.run("Process payment for customer John Doe")
      runner.run("Update user email to john@example.com")
      
      # Generate compliance report
      report = compliance_monitor.generate_report
      puts "\nCompliance Report:"
      puts "- GDPR Score: #{report[:gdpr][:score]}%"
      puts "- SOC2 Score: #{report[:soc2][:score]}%"
      puts "- Total events logged: #{audit_logger.event_count}"
      
      # Export audit logs
      audit_logger.export_logs(format: :json, output_file: "audit_export.json")
      puts "Audit logs exported to audit_export.json"
    end
  end

  def multi_provider_examples
    section "Multi-Provider Support" do
      # Structured output schema that works with all providers
      user_schema = {
        type: "object",
        properties: {
          name: { type: "string" },
          role: { type: "string" },
          skills: {
            type: "array",
            items: { type: "string" }
          },
          experience_years: { type: "integer" }
        },
        required: ["name", "role", "skills"]
      }
      
      # Test with different providers
      providers = [
        { name: "OpenAI", model: "gpt-4o", provider: nil }, # Default
        { name: "Anthropic", model: "claude-3-sonnet-20240229", provider: OpenAIAgents::Models::AnthropicProvider.new },
        # Add other providers as needed
      ]
      
      providers.each do |config|
        next unless ENV["#{config[:name].upcase}_API_KEY"]
        
        puts "\nTesting with #{config[:name]}:"
        
        agent = OpenAIAgents::Agent.new(
          name: "#{config[:name]}Agent",
          instructions: "Extract user information from the text.",
          model: config[:model],
          provider: config[:provider],
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "user_info",
              strict: true,
              schema: user_schema
            }
          }
        )
        
        runner = OpenAIAgents::Runner.new(agent: agent)
        
        begin
          result = runner.run("I'm Sarah, a senior developer with 8 years of experience in Ruby, Python, and JavaScript")
          user_data = JSON.parse(result.messages.last[:content])
          puts "Extracted data: #{user_data.inspect}"
        rescue => e
          puts "Error: #{e.message}"
        end
      end
    end
  end

  def streaming_examples
    section "Streaming & Events" do
      agent = OpenAIAgents::Agent.new(
        name: "StreamingAgent",
        instructions: "You are a helpful assistant who provides detailed explanations.",
        model: "gpt-4o"
      )
      
      runner = OpenAIAgents::Runner.new(agent: agent)
      
      puts "Streaming response with event handling:"
      puts "-" * 50
      
      total_tokens = 0
      start_time = Time.now
      
      runner.run_streaming("Explain the concept of recursion in programming with an example") do |event|
        case event
        when OpenAIAgents::StreamingEvents::ResponseCreatedEvent
          puts "\n[Response started]"
          
        when OpenAIAgents::StreamingEvents::ResponseTextDeltaEvent
          print event.text_delta
          $stdout.flush
          
        when OpenAIAgents::StreamingEvents::ResponseCompletedEvent
          elapsed = Time.now - start_time
          puts "\n\n[Response completed in #{elapsed.round(2)}s]"
          
          if event.usage
            total_tokens = event.usage[:total_tokens]
            puts "[Tokens used: #{total_tokens}]"
          end
          
        when OpenAIAgents::StreamingEvents::ErrorEvent
          puts "\n[Error: #{event.error.message}]"
        end
      end
      
      puts "\n" + "-" * 50
    end
  end

  def advanced_tools_examples
    section "Advanced Tools" do
      # MCP Tool example (if MCP server is available)
      if ENV['MCP_SERVER_COMMAND']
        mcp_tool = OpenAIAgents::Tools::MCPTool.new(
          server_name: "demo-mcp-server",
          transport: :stdio,
          command: ENV['MCP_SERVER_COMMAND'],
          args: ENV['MCP_SERVER_ARGS']&.split(' ') || []
        )
        
        agent = OpenAIAgents::Agent.new(
          name: "MCPAgent",
          instructions: "Use MCP tools to help users.",
          model: "gpt-4o"
        )
        
        # Discover and add MCP tools
        discovered_tools = mcp_tool.discover_tools
        puts "Discovered #{discovered_tools.length} MCP tools"
        discovered_tools.each { |tool| agent.add_tool(tool) }
      end
      
      # Local Shell Tool (safe commands only)
      shell_tool = OpenAIAgents::Tools::LocalShellTool.new(
        allowed_commands: ["date", "echo", "pwd", "ls"],
        working_directory: ".",
        timeout: 5
      )
      
      agent = OpenAIAgents::Agent.new(
        name: "SystemAgent",
        instructions: "Help with safe system commands.",
        model: "gpt-4o"
      )
      
      agent.add_tool(shell_tool)
      
      runner = OpenAIAgents::Runner.new(agent: agent)
      result = runner.run("What's the current date and list files in the current directory?")
      puts "\nSystem command result: #{result.messages.last[:content]}"
    end
  end

  def section(title)
    puts "\n#{'=' * 60}"
    puts "## #{title}"
    puts "#{'=' * 60}\n"
    yield
  rescue => e
    puts "\nError in #{title}: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end

# Run all examples if executed directly
if __FILE__ == $0
  ComprehensiveExamples.run_all
end