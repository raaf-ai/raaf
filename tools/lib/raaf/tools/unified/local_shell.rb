# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "../../../../../lib/raaf/tool"

module RAAF
  module Tools
    module Unified
      # Local Shell Execution Tool
      #
      # Executes shell commands locally with safety controls and timeout management.
      # Use with caution - this tool can execute arbitrary commands.
      #
      class LocalShellTool < RAAF::Tool
        configure description: "Execute shell commands on the local system"

        parameters do
          property :command, type: "string", description: "Shell command to execute"
          property :timeout, type: "integer", description: "Timeout in seconds"
          property :working_dir, type: "string", description: "Working directory for command"
          required :command
        end

        def initialize(allowed_commands: nil, max_timeout: 30, safe_mode: true, **options)
          super(**options)
          @allowed_commands = allowed_commands
          @max_timeout = max_timeout
          @safe_mode = safe_mode
        end

        def call(command:, timeout: nil, working_dir: nil)
          validate_command(command) if @safe_mode
          
          timeout ||= @max_timeout
          timeout = [@max_timeout, timeout].min

          execute_command(command, timeout, working_dir)
        end

        private

        def validate_command(command)
          # Basic safety checks
          dangerous_patterns = [
            /rm\s+-rf\s+\//,    # Dangerous rm commands
            /:(){ :|:& };:/,     # Fork bomb
            />\s*\/dev\/sd/,     # Direct disk writes
            /dd\s+if=/,          # dd commands
            /mkfs/,              # Format commands
          ]

          dangerous_patterns.each do |pattern|
            if command.match?(pattern)
              raise SecurityError, "Command contains potentially dangerous pattern"
            end
          end

          # Check allowed commands if configured
          if @allowed_commands
            base_command = command.split.first
            unless @allowed_commands.include?(base_command)
              raise SecurityError, "Command '#{base_command}' not in allowed list"
            end
          end
        end

        def execute_command(command, timeout, working_dir)
          result = {
            command: command,
            executed_at: Time.now.iso8601
          }

          options = {}
          options[:chdir] = working_dir if working_dir && Dir.exist?(working_dir)

          begin
            Timeout.timeout(timeout) do
              stdout, stderr, status = Open3.capture3(command, **options)
              
              result[:stdout] = stdout
              result[:stderr] = stderr
              result[:exit_code] = status.exitstatus
              result[:success] = status.success?
            end
          rescue Timeout::Error
            result[:error] = "Command timed out after #{timeout} seconds"
            result[:success] = false
          rescue StandardError => e
            result[:error] = e.message
            result[:success] = false
          end

          format_result(result)
        end

        def format_result(result)
          output = "Command: #{result[:command]}\n"
          output += "Status: #{result[:success] ? 'Success' : 'Failed'}\n"
          output += "Exit Code: #{result[:exit_code]}\n" if result[:exit_code]
          output += "\nOutput:\n#{result[:stdout]}" if result[:stdout] && !result[:stdout].empty?
          output += "\nErrors:\n#{result[:stderr]}" if result[:stderr] && !result[:stderr].empty?
          output += "\nError: #{result[:error]}" if result[:error]
          output
        end
      end

      # Advanced Shell Tool with session management
      #
      # Maintains shell session state across multiple commands
      #
      class AdvancedShellTool < LocalShellTool
        configure name: "advanced_shell",
                 description: "Execute shell commands with session persistence"

        def initialize(**options)
          super(**options)
          @session_env = {}
          @session_dir = Dir.pwd
        end

        def call(command:, timeout: nil, working_dir: nil)
          # Update session directory if changed
          @session_dir = working_dir if working_dir

          # Execute with session context
          full_command = build_session_command(command)
          super(command: full_command, timeout: timeout, working_dir: @session_dir)
        end

        private

        def build_session_command(command)
          # Preserve environment variables across commands
          env_setup = @session_env.map { |k, v| "export #{k}=#{v}" }.join("; ")
          env_setup.empty? ? command : "#{env_setup}; #{command}"
        end
      end
    end
  end
end