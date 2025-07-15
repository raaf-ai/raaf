# frozen_string_literal: true

require "json"

# Advanced debugging utilities for Swarm-style multi-agent workflows
#
# This class provides comprehensive debugging and visualization capabilities
# for context variable flow, agent handoffs, and multi-agent orchestration.
# It helps developers understand complex workflow execution and debug issues
# in multi-agent systems.
#
# Key features:
# - Real-time context variable tracking
# - Handoff decision tree visualization
# - Agent execution flow mapping
# - Performance metrics and timing
# - Interactive debugging sessions
# - Context diff visualization
#
# @example Basic debugging
#   debugger = AiAgentDsl::SwarmDebugger.new(enabled: true)
#   debugger.start_workflow_session("Customer Support Triage")
#
#   # Agent execution with debugging
#   result = debugger.debug_agent_execution(agent, context_vars) do
#     agent.run(input_context_variables: context_vars)
#   end
#
# @example Handoff debugging
#   debugger.debug_handoff_decision(
#     from_agent: triage_agent,
#     to_agent: specialist_agent,
#     context_variables: context_vars,
#     reason: "High priority technical issue"
#   )
#
# @since 0.2.0
#
class AiAgentDsl::SwarmDebugger
  # @return [Boolean] Whether debugging is enabled
  attr_reader :enabled

  # @return [Array<Hash>] Execution trace for the current session
  attr_reader :execution_trace

  # @return [Hash] Current workflow session information
  attr_reader :current_session

  # @return [IO] Output destination for debug information
  attr_reader :output

  # Initialize a new SwarmDebugger instance
  #
  # @param enabled [Boolean] Enable debugging output
  # @param output [IO] Where to write debug output (default: STDOUT)
  # @param trace_limit [Integer] Maximum number of trace entries to keep
  #
  def initialize(enabled: true, output: $stdout, trace_limit: 1000)
    @enabled = enabled
    @output = output
    @trace_limit = trace_limit
    @execution_trace = []
    @current_session = nil
    @session_start_time = nil
  end

  # Start a new debugging session for a multi-agent workflow
  #
  # @param workflow_name [String] Name of the workflow being debugged
  # @param initial_context [ContextVariables, Hash] Initial context variables
  # @param metadata [Hash] Additional session metadata
  #
  def start_workflow_session(workflow_name, initial_context: nil, metadata: {})
    return unless @enabled

    @session_start_time = Time.current
    @current_session = {
      workflow_name:      workflow_name,
      session_id:         generate_session_id,
      start_time:         @session_start_time,
      initial_context:    initial_context.to_h,
      metadata:           metadata,
      agents_executed:    [],
      handoffs_performed: [],
      context_evolution:  []
    }

    @execution_trace.clear

    debug_output("=" * 80)
    debug_output("🚀 SWARM DEBUG SESSION STARTED")
    debug_output("=" * 80)
    debug_output("Workflow: #{workflow_name}")
    debug_output("Session ID: #{@current_session[:session_id]}")
    debug_output("Start Time: #{@session_start_time}")
    if initial_context && !initial_context.empty?
      debug_output("\n📋 INITIAL CONTEXT VARIABLES:")
      pretty_print_context(initial_context)
    end
    debug_output("=" * 80)
    debug_output("")
  end

  # End the current debugging session with summary
  #
  def end_workflow_session
    return unless @enabled || @current_session

    session_duration = Time.current - @session_start_time

    debug_output("\n#{'=' * 80}")
    debug_output("🏁 SWARM DEBUG SESSION ENDED")
    debug_output("=" * 80)
    debug_output("Workflow: #{@current_session[:workflow_name]}")
    debug_output("Session ID: #{@current_session[:session_id]}")
    debug_output("Duration: #{format_duration(session_duration)}")
    debug_output("Agents Executed: #{@current_session[:agents_executed].size}")
    debug_output("Handoffs Performed: #{@current_session[:handoffs_performed].size}")
    debug_output("Context Changes: #{@current_session[:context_evolution].size}")
    debug_output("Trace Entries: #{@execution_trace.size}")
    debug_output("=" * 80)

    # Generate session summary
    summary = generate_session_summary
    debug_output("\n📊 SESSION SUMMARY:")
    debug_output(summary)

    @current_session = nil
    @session_start_time = nil
  end

  # Debug agent execution with comprehensive logging
  #
  # @param agent [Base] The agent being executed
  # @param context_variables [ContextVariables] Context variables for execution
  # @param metadata [Hash] Additional execution metadata
  # @yield Block that executes the agent
  # @return [Object] Result of the agent execution
  #
  def debug_agent_execution(agent, context_variables, metadata: {})
    return yield unless @enabled

    execution_id = SecureRandom.hex(8)
    start_time = Time.current

    # Log execution start
    debug_output("🤖 AGENT EXECUTION STARTED")
    debug_output(("-" * 60).to_s)
    debug_output("Execution ID: #{execution_id}")
    debug_output("Agent: #{agent.class.name} (#{agent.agent_name})")
    debug_output("Model: #{agent.model_name}")
    debug_output("Max Turns: #{agent.max_turns}")
    debug_output("Tools: #{agent.tools.map(&:tool_name).join(', ')}") if agent.tools.any?
    debug_output("Start Time: #{start_time}")

    # Show context variables
    debug_output("\n📋 CONTEXT VARIABLES AT START:")
    pretty_print_context(context_variables)

    # Show system prompt
    begin
      system_prompt = agent.build_instructions
      debug_output("\n📝 SYSTEM PROMPT:")
      debug_output(format_prompt_preview(system_prompt))
    rescue StandardError => e
      debug_output("\n❌ Error building system prompt: #{e.message}")
    end

    # Show user prompt
    begin
      user_prompt = agent.build_user_prompt
      if user_prompt && !user_prompt.empty?
        debug_output("\n💬 USER PROMPT:")
        debug_output(format_prompt_preview(user_prompt))
      end
    rescue StandardError => e
      debug_output("\n❌ Error building user prompt: #{e.message}")
    end

    debug_output(("-" * 60).to_s)

    # Execute and capture result
    begin
      result = yield
      execution_time = Time.current - start_time

      # Log execution complete
      debug_output("\n✅ AGENT EXECUTION COMPLETED")
      debug_output(("-" * 60).to_s)
      debug_output("Execution ID: #{execution_id}")
      debug_output("Duration: #{format_duration(execution_time)}")
      debug_output("Status: #{result[:workflow_status] || 'unknown'}")
      debug_output("Success: #{result[:success] || 'unknown'}")

      # Show result
      if result[:results]
        debug_output("\n📤 EXECUTION RESULTS:")
        debug_output(format_result_preview(result[:results]))
      end

      # Show context variables after execution
      if result[:context_variables]
        debug_output("\n📋 CONTEXT VARIABLES AFTER EXECUTION:")
        pretty_print_context(result[:context_variables])

        # Show context changes
        context_diff = context_variables.diff(result[:context_variables])
        unless context_diff[:identical]
          debug_output("\n🔄 CONTEXT CHANGES:")
          debug_output(format_context_diff(context_diff))
        end
      end

      # Add to session tracking
      track_agent_execution(agent, context_variables, result, execution_time, metadata)

      debug_output(("-" * 60).to_s)
      debug_output("")

      result
    rescue StandardError => e
      execution_time = Time.current - start_time

      debug_output("\n❌ AGENT EXECUTION FAILED")
      debug_output(("-" * 60).to_s)
      debug_output("Execution ID: #{execution_id}")
      debug_output("Duration: #{format_duration(execution_time)}")
      debug_output("Error: #{e.class.name}: #{e.message}")
      debug_output("Backtrace: #{e.backtrace.first(3).join(', ')}")
      debug_output(("-" * 60).to_s)
      debug_output("")

      raise e
    end
  end

  # Debug handoff decision and execution
  #
  # @param from_agent [Base] Agent initiating the handoff
  # @param to_agent [Base] Agent receiving the handoff
  # @param context_variables [ContextVariables] Context at time of handoff
  # @param reason [String] Reason for the handoff
  # @param metadata [Hash] Additional handoff metadata
  #
  def debug_handoff_decision(from_agent:, to_agent:, context_variables:, reason: nil, metadata: {})
    return unless @enabled

    handoff_id = SecureRandom.hex(8)
    timestamp = Time.current

    debug_output("🔄 HANDOFF DECISION")
    debug_output(("-" * 60).to_s)
    debug_output("Handoff ID: #{handoff_id}")
    debug_output("From Agent: #{from_agent.class.name} (#{from_agent.agent_name})")
    debug_output("To Agent: #{to_agent.class.name} (#{to_agent.agent_name})")
    debug_output("Timestamp: #{timestamp}")
    debug_output("Reason: #{reason || 'Not specified'}")

    debug_output("\n📋 CONTEXT VARIABLES AT HANDOFF:")
    pretty_print_context(context_variables)

    # Analyze handoff logic
    debug_output("\n🧠 HANDOFF ANALYSIS:")
    debug_output("From Agent Tools: #{from_agent.tools.map(&:tool_name).join(', ')}")
    debug_output("To Agent Tools: #{to_agent.tools.map(&:tool_name).join(', ')}")
    debug_output("Context Variables: #{context_variables.size} variables")

    # Track handoff
    track_handoff(from_agent, to_agent, context_variables, reason, metadata)

    debug_output(("-" * 60).to_s)
    debug_output("")
  end

  # Debug context variable evolution over time
  #
  # @param title [String] Title for this context evolution step
  # @param before_context [ContextVariables] Context before the change
  # @param after_context [ContextVariables] Context after the change
  # @param operation [String] Description of what caused the change
  #
  def debug_context_evolution(title, before_context:, after_context:, operation: nil)
    return unless @enabled

    debug_output("📈 CONTEXT EVOLUTION: #{title}")
    debug_output(("-" * 60).to_s)
    debug_output("Operation: #{operation || 'Unknown'}") if operation
    debug_output("Timestamp: #{Time.current}")

    # Calculate and show diff
    diff = before_context.diff(after_context)

    if diff[:identical]
      debug_output("No changes to context variables")
    else
      debug_output("\n🔄 CHANGES DETECTED:")
      debug_output(format_context_diff(diff))
    end

    # Track evolution
    track_context_evolution(title, before_context, after_context, operation)

    debug_output(("-" * 60).to_s)
    debug_output("")
  end

  # Generate a comprehensive debug report
  #
  # @param include_trace [Boolean] Include full execution trace
  # @return [String] Formatted debug report
  #
  def generate_debug_report(include_trace: false)
    return "Debug not enabled" unless @enabled

    report = []
    report << ("=" * 80)
    report << "🔍 SWARM DEBUG REPORT"
    report << ("=" * 80)
    report << ""

    if @current_session
      report << "📋 SESSION INFORMATION:"
      report << "Workflow: #{@current_session[:workflow_name]}"
      report << "Session ID: #{@current_session[:session_id]}"
      report << "Duration: #{format_duration(Time.current - @session_start_time)}"
      report << "Agents Executed: #{@current_session[:agents_executed].size}"
      report << "Handoffs: #{@current_session[:handoffs_performed].size}"
      report << "Context Changes: #{@current_session[:context_evolution].size}"
      report << ""
    end

    report << "📊 EXECUTION STATISTICS:"
    report << "Total Trace Entries: #{@execution_trace.size}"
    if @execution_trace.any?
      avg_duration = @execution_trace.map { |t| t[:duration] }.compact.sum / @execution_trace.size.to_f
      report << "Average Execution Time: #{format_duration(avg_duration)}"
    end
    report << ""

    if include_trace && @execution_trace.any?
      report << "🗂 EXECUTION TRACE:"
      report << ("-" * 40)
      @execution_trace.each_with_index do |entry, i|
        report << "#{i + 1}. #{entry[:timestamp]} - #{entry[:type]}: #{entry[:summary]}"
      end
      report << ""
    end

    report << ("=" * 80)
    report.join("\n")
  end

  # Interactive debugging session
  #
  # @param agent [Base] Agent to debug interactively
  # @param initial_context [ContextVariables] Starting context
  #
  def interactive_debug_session(agent, initial_context)
    return unless @enabled

    debug_output("🐛 INTERACTIVE DEBUG SESSION STARTED")
    debug_output("Type 'help' for available commands, 'quit' to exit")
    debug_output("")

    current_context = initial_context
    turn = 0

    loop do
      turn += 1
      debug_output("debug[#{turn}]> ", newline: false)
      command = $stdin.gets&.chomp&.strip

      break if command.nil? || command == "quit"

      case command
      when "help"
        show_debug_help
      when "context"
        pretty_print_context(current_context)
      when "prompt"
        show_agent_prompts(agent)
      when "tools"
        show_agent_tools(agent)
      when "run"
        result = debug_agent_execution(agent, current_context) do
          agent.run(input_context_variables: current_context)
        end
        current_context = result[:context_variables] || current_context
      when "step"
        debug_output("Single-step execution not yet implemented")
      when "trace"
        show_execution_trace
      when "report"
        debug_output(generate_debug_report)
      else
        debug_output("Unknown command: #{command}. Type 'help' for available commands.")
      end

      debug_output("")
    end

    debug_output("🐛 Interactive debug session ended")
  end

  private

  # Generate unique session ID
  def generate_session_id
    "swarm-#{Time.current.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}"
  end

  # Format duration in human-readable format
  def format_duration(seconds)
    if seconds < 1
      "#{(seconds * 1000).round(1)}ms"
    elsif seconds < 60
      "#{seconds.round(2)}s"
    else
      "#{(seconds / 60).round(1)}m"
    end
  end

  # Pretty print context variables
  def pretty_print_context(context_variables)
    if context_variables.nil? || context_variables.empty?
      debug_output("  (empty)")
      return
    end

    context_hash = context_variables.respond_to?(:to_h) ? context_variables.to_h : context_variables

    context_hash.each do |key, value|
      debug_output("  #{key}: #{format_value_preview(value)}")
    end
  end

  # Format a value for preview (truncate if too long)
  def format_value_preview(value, max_length: 100)
    str = value.inspect
    if str.length > max_length
      "#{str[0, max_length - 3]}..."
    else
      str
    end
  end

  # Format prompt preview
  def format_prompt_preview(prompt, max_lines: 10)
    return "(empty)" if prompt.nil? || prompt.empty?

    lines = prompt.split("\n")
    if lines.size > max_lines
      preview_lines = lines.first(max_lines)
      preview_lines << "... (#{lines.size - max_lines} more lines)"
      preview_lines.join("\n")
    else
      prompt
    end
  end

  # Format result preview
  def format_result_preview(result, max_length: 200)
    preview = if result.is_a?(Hash)
                result.inspect
              else
                result.to_s
              end

    if preview.length > max_length
      "#{preview[0, max_length - 3]}..."
    else
      preview
    end
  end

  # Format context diff for display
  def format_context_diff(diff)
    lines = []

    if diff[:added].any?
      lines << "  ➕ Added (#{diff[:added].size}):"
      diff[:added].each { |k, v| lines << "     #{k}: #{format_value_preview(v)}" }
    end

    if diff[:removed].any?
      lines << "  ➖ Removed (#{diff[:removed].size}):"
      diff[:removed].each { |k, v| lines << "     #{k}: #{format_value_preview(v)}" }
    end

    if diff[:changed].any?
      lines << "  🔄 Changed (#{diff[:changed].size}):"
      diff[:changed].each do |k, change|
        lines << "     #{k}: #{format_value_preview(change[:from])} → #{format_value_preview(change[:to])}"
      end
    end

    lines.empty? ? "  No changes" : lines.join("\n")
  end

  # Track agent execution in session
  def track_agent_execution(agent, context_variables, result, duration, metadata)
    return unless @current_session

    execution_info = {
      agent_class:       agent.class.name,
      agent_name:        agent.agent_name,
      context_variables: context_variables.to_h,
      result_status:     result[:workflow_status],
      duration:          duration,
      timestamp:         Time.current,
      metadata:          metadata
    }

    @current_session[:agents_executed] << execution_info

    add_to_trace(
      type:    :agent_execution,
      summary: "#{agent.agent_name} executed (#{format_duration(duration)})",
      details: execution_info
    )
  end

  # Track handoff in session
  def track_handoff(from_agent, to_agent, context_variables, reason, metadata)
    return unless @current_session

    handoff_info = {
      from_agent:        from_agent.agent_name,
      to_agent:          to_agent.agent_name,
      context_variables: context_variables.to_h,
      reason:            reason,
      timestamp:         Time.current,
      metadata:          metadata
    }

    @current_session[:handoffs_performed] << handoff_info

    add_to_trace(
      type:    :handoff,
      summary: "Handoff: #{from_agent.agent_name} → #{to_agent.agent_name}",
      details: handoff_info
    )
  end

  # Track context evolution in session
  def track_context_evolution(title, before_context, after_context, operation)
    return unless @current_session

    evolution_info = {
      title:     title,
      operation: operation,
      before:    before_context.to_h,
      after:     after_context.to_h,
      diff:      before_context.diff(after_context),
      timestamp: Time.current
    }

    @current_session[:context_evolution] << evolution_info

    add_to_trace(
      type:    :context_evolution,
      summary: "Context: #{title}",
      details: evolution_info
    )
  end

  # Add entry to execution trace
  def add_to_trace(type:, summary:, details: {})
    @execution_trace << {
      type:      type,
      summary:   summary,
      details:   details,
      timestamp: Time.current
    }

    # Keep trace size manageable
    @execution_trace.shift if @execution_trace.size > @trace_limit
  end

  # Generate session summary
  def generate_session_summary
    return "No active session" unless @current_session

    lines = []
    lines << "Workflow: #{@current_session[:workflow_name]}"
    lines << "Agents: #{@current_session[:agents_executed].map { |a| a[:agent_name] }.uniq.join(', ')}"
    lines << "Handoffs: #{@current_session[:handoffs_performed].size}"
    lines << "Context Changes: #{@current_session[:context_evolution].size}"

    if @current_session[:agents_executed].any?
      total_time = @current_session[:agents_executed].sum { |a| a[:duration] }
      lines << "Total Execution Time: #{format_duration(total_time)}"
    end

    lines.join("\n")
  end

  # Show debug help
  def show_debug_help
    debug_output("Available commands:")
    debug_output("  help     - Show this help")
    debug_output("  context  - Show current context variables")
    debug_output("  prompt   - Show agent prompts")
    debug_output("  tools    - Show agent tools")
    debug_output("  run      - Execute agent with current context")
    debug_output("  step     - Execute single step (not implemented)")
    debug_output("  trace    - Show execution trace")
    debug_output("  report   - Generate debug report")
    debug_output("  quit     - Exit debug session")
  end

  # Show agent prompts
  def show_agent_prompts(agent)
    debug_output("System Prompt:")
    debug_output(agent.build_instructions)
    debug_output("")

    user_prompt = agent.build_user_prompt
    if user_prompt && !user_prompt.empty?
      debug_output("User Prompt:")
      debug_output(user_prompt)
    else
      debug_output("User Prompt: (empty)")
    end
  rescue StandardError => e
    debug_output("Error showing prompts: #{e.message}")
  end

  # Show agent tools
  def show_agent_tools(agent)
    if agent.tools.empty?
      debug_output("No tools configured")
    else
      debug_output("Tools (#{agent.tools.size}):")
      agent.tools.each do |tool|
        debug_output("  - #{tool.tool_name}")
      end
    end
  end

  # Show execution trace
  def show_execution_trace
    if @execution_trace.empty?
      debug_output("No trace entries")
    else
      debug_output("Execution Trace (#{@execution_trace.size} entries):")
      @execution_trace.last(10).each_with_index do |entry, i|
        debug_output("  #{i + 1}. #{entry[:timestamp].strftime('%H:%M:%S')} - #{entry[:type]}: #{entry[:summary]}")
      end
      debug_output("  (showing last 10 entries)") if @execution_trace.size > 10
    end
  end

  # Output debug information
  def debug_output(text, newline: true)
    if newline
      @output.puts(text)
    else
      @output.print(text)
    end
    @output.flush
  end
end
