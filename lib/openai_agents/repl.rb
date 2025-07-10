# frozen_string_literal: true

require "readline"
require "io/console"
require_relative "agent"
require_relative "runner"
require_relative "tracing/spans"
require_relative "logging"

module OpenAIAgents
  class REPL
    include Logger
    COMMANDS = {
      "/help" => "Show this help message",
      "/agents" => "List all available agents",
      "/current" => "Show current agent",
      "/switch <agent>" => "Switch to a different agent",
      "/new <name>" => "Create a new agent",
      "/tools" => "List tools for current agent",
      "/trace" => "Show trace summary",
      "/clear" => "Clear conversation history",
      "/export" => "Export conversation to file",
      "/load <file>" => "Load conversation from file",
      "/quit" => "Exit the REPL",
      "/debug" => "Toggle debug mode",
      "/model <model>" => "Change model for current agent",
      "/instructions <text>" => "Update agent instructions",
      "/add_tool <name>" => "Add a tool to current agent",
      "/history" => "Show conversation history",
      "/reset" => "Reset current agent state"
    }.freeze

    def initialize(agent: nil, tracer: nil, debug: false)
      @agents = {}
      @current_agent_name = nil
      @conversation = []
      @tracer = tracer || Tracing::SpanTracer.new
      @debug = debug
      @running = false

      if agent
        add_agent(agent)
        switch_agent(agent.name)
      end

      setup_readline
      setup_default_tools
    end

    def start
      @running = true
      show_welcome

      while @running
        begin
          input = readline_with_prompt
          next if input.nil? || input.strip.empty?

          if input.start_with?("/")
            handle_command(input.strip)
          else
            handle_user_message(input.strip)
          end
        rescue Interrupt
          puts "\nUse /quit to exit"
        rescue StandardError => e
          log_error("REPL error: #{e.message}", error_class: e.class.name)
          puts "Error: #{e.message}"
          puts e.backtrace.first(5).join("\n") if @debug
        end
      end

      show_goodbye
    end

    private

    def setup_readline
      Readline.completion_proc = proc do |str|
        commands = COMMANDS.keys
        agent_names = @agents.keys.map { |name| "/switch #{name}" }

        (commands + agent_names).grep(/^#{Regexp.escape(str)}/)
      end
    end

    def setup_default_tools
      # Add some useful default tools
      # rubocop:disable Lint/NestedMethodDefinition
      def weather_tool(city)
        "The weather in #{city} is sunny with 22°C"
      end

      def time_tool
        Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
      end

      def calculator_tool(expression)
        # rubocop:disable Security/Eval
        result = eval(expression)
        # rubocop:enable Security/Eval
        "Result: #{result}"
      rescue StandardError
        "Invalid expression"
      end
      # rubocop:enable Lint/NestedMethodDefinition

      @default_tools = {
        "weather" => method(:weather_tool),
        "time" => method(:time_tool),
        "calculator" => method(:calculator_tool)
      }
    end

    def show_welcome
      puts "🤖 OpenAI Agents Ruby REPL"
      puts "=" * 40
      puts "Type /help for available commands"
      puts "Type your message to chat with the agent"
      puts

      if @current_agent_name
        puts "Current agent: #{@current_agent_name}"
      else
        puts "No agent selected. Use /new <name> to create one."
      end
      puts
    end

    def show_goodbye
      puts "\n👋 Goodbye!"
    end

    def readline_with_prompt
      prompt = if @current_agent_name
                 "#{@current_agent_name}> "
               else
                 "agents> "
               end

      Readline.readline(prompt, true)
    end

    def handle_command(input)
      parts = input.split(" ", 2)
      command = parts[0]
      args = parts[1]

      case command
      when "/help"
        show_help
      when "/agents"
        list_agents
      when "/current"
        show_current_agent
      when "/switch"
        switch_agent(args) if args
      when "/new"
        create_agent(args) if args
      when "/tools"
        list_tools
      when "/trace"
        show_trace_summary
      when "/clear"
        clear_conversation
      when "/export"
        export_conversation(args)
      when "/load"
        load_conversation(args) if args
      when "/quit", "/exit"
        @running = false
      when "/debug"
        toggle_debug
      when "/model"
        change_model(args) if args
      when "/instructions"
        update_instructions(args) if args
      when "/add_tool"
        add_tool_interactive(args) if args
      when "/history"
        show_history
      when "/reset"
        reset_agent
      else
        puts "Unknown command: #{command}. Type /help for available commands."
      end
    end

    def handle_user_message(message)
      unless current_agent
        puts "No agent selected. Use /new <name> to create an agent first."
        return
      end

      @conversation << { role: "user", content: message }

      begin
        @tracer.agent_span(current_agent.name, message: message) do |span|
          runner = Runner.new(agent: current_agent, tracer: @tracer)
          result = runner.run(@conversation.dup)

          if result[:messages]
            # Update conversation with agent's response
            assistant_messages = result[:messages].select { |msg| msg[:role] == "assistant" }
            @conversation.concat(assistant_messages)

            # Display response
            assistant_messages.each do |msg|
              puts "#{current_agent.name}: #{msg[:content]}"
            end
          end

          span.set_attribute("turns", result[:turns])
          span.set_attribute("total_messages", @conversation.length)
        end
      rescue StandardError => e
        log_error("Agent interaction error: #{e.message}",
                  agent: @current_agent_name,
                  error_class: e.class.name)
        puts "Error: #{e.message}"
        puts e.backtrace.first(3).join("\n") if @debug
      end
    end

    def show_help
      puts "Available commands:"
      puts
      COMMANDS.each do |cmd, desc|
        puts "  #{cmd.ljust(20)} - #{desc}"
      end
      puts
    end

    def list_agents
      if @agents.empty?
        puts "No agents available. Use /new <name> to create one."
      else
        puts "Available agents:"
        @agents.each do |name, agent|
          current_marker = name == @current_agent_name ? " (current)" : ""
          puts "  - #{name}#{current_marker}"
          puts "    Model: #{agent.model}"
          puts "    Tools: #{agent.tools.length}"
          puts "    Handoffs: #{agent.handoffs.length}"
          puts
        end
      end
    end

    def show_current_agent
      agent = current_agent
      unless agent
        puts "No agent currently selected."
        return
      end

      puts "Current agent: #{agent.name}"
      puts "Model: #{agent.model}"
      puts "Instructions: #{agent.instructions || "None"}"
      puts "Tools: #{agent.tools.length}"
      puts "Handoffs: #{agent.handoffs.length}"
      puts "Max turns: #{agent.max_turns}"
    end

    def switch_agent(name)
      unless @agents.key?(name)
        puts "Agent '#{name}' not found. Available agents: #{@agents.keys.join(", ")}"
        return
      end

      @current_agent_name = name
      puts "Switched to agent: #{name}"
    end

    def create_agent(name)
      if @agents.key?(name)
        puts "Agent '#{name}' already exists."
        return
      end

      puts "Creating new agent: #{name}"
      print "Model (default: gpt-4): "
      model = Readline.readline.strip
      model = "gpt-4" if model.empty?

      print "Instructions: "
      instructions = Readline.readline

      agent = Agent.new(
        name: name,
        instructions: instructions.empty? ? nil : instructions,
        model: model
      )

      add_agent(agent)
      switch_agent(name)
      puts "Agent '#{name}' created successfully!"
    end

    def add_agent(agent)
      @agents[agent.name] = agent
    end

    def current_agent
      @current_agent_name ? @agents[@current_agent_name] : nil
    end

    def list_tools
      agent = current_agent
      unless agent
        puts "No agent selected."
        return
      end

      if agent.tools.empty?
        puts "No tools available for #{agent.name}."
        puts "Default tools available: #{@default_tools.keys.join(", ")}"
      else
        puts "Tools for #{agent.name}:"
        agent.tools.each do |tool|
          puts "  - #{tool.name}: #{tool.description}"
        end
      end
    end

    def show_trace_summary
      summary = @tracer.trace_summary
      if summary
        puts "Trace Summary:"
        puts "  Trace ID: #{summary[:trace_id]}"
        puts "  Total spans: #{summary[:total_spans]}"
        puts "  Duration: #{summary[:total_duration_ms]}ms"
        puts "  Status: #{summary[:status]}"
        puts "  Start: #{summary[:start_time]}"
        puts "  End: #{summary[:end_time]}"
      else
        puts "No trace data available."
      end
    end

    def clear_conversation
      @conversation.clear
      @tracer.clear
      puts "Conversation and trace data cleared."
    end

    def export_conversation(filename)
      filename ||= "conversation_#{Time.now.strftime("%Y%m%d_%H%M%S")}.json"

      data = {
        timestamp: Time.now.utc.iso8601,
        agent: @current_agent_name,
        conversation: @conversation,
        trace_summary: @tracer.trace_summary,
        spans: @tracer.export_spans(format: :hash)
      }

      File.write(filename, JSON.pretty_generate(data))
      puts "Conversation exported to: #{filename}"
    end

    def load_conversation(filename)
      unless File.exist?(filename)
        puts "File not found: #{filename}"
        return
      end

      begin
        data = JSON.parse(File.read(filename))
        @conversation = data["conversation"] || []

        puts "Conversation loaded from: #{filename}"
        puts "Messages: #{@conversation.length}"
        puts "Original agent: #{data["agent"]}" if data["agent"]
      rescue JSON::ParserError => e
        log_error("JSON parsing error: #{e.message}", filename: filename)
        puts "Error parsing file: #{e.message}"
      end
    end

    def toggle_debug
      @debug = !@debug
      puts "Debug mode: #{@debug ? "ON" : "OFF"}"
    end

    def change_model(model)
      agent = current_agent
      unless agent
        puts "No agent selected."
        return
      end

      agent.model = model
      puts "Model changed to: #{model}"
    end

    def update_instructions(instructions)
      agent = current_agent
      unless agent
        puts "No agent selected."
        return
      end

      agent.instructions = instructions
      puts "Instructions updated."
    end

    def add_tool_interactive(tool_name)
      agent = current_agent
      unless agent
        puts "No agent selected."
        return
      end

      if @default_tools.key?(tool_name)
        agent.add_tool(@default_tools[tool_name])
        puts "Added tool: #{tool_name}"
      else
        puts "Unknown tool: #{tool_name}"
        puts "Available default tools: #{@default_tools.keys.join(", ")}"
      end
    end

    def show_history
      if @conversation.empty?
        puts "No conversation history."
        return
      end

      puts "Conversation History (#{@conversation.length} messages):"
      puts "=" * 50

      @conversation.each_with_index do |msg, index|
        role_label = case msg[:role]
                     when "user" then "You"
                     when "assistant" then current_agent&.name || "Assistant"
                     when "system" then "System"
                     when "tool" then "Tool"
                     else msg[:role].capitalize
                     end

        puts "#{index + 1}. #{role_label}: #{msg[:content]}"
        puts
      end
    end

    def reset_agent
      agent = current_agent
      unless agent
        puts "No agent selected."
        return
      end

      # Reset agent state (clear tools, reset to defaults)
      agent.tools.clear
      agent.handoffs.clear
      puts "Agent '#{agent.name}' has been reset."
    end
  end
end
