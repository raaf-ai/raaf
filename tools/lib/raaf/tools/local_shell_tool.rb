# frozen_string_literal: true

require "open3"
require "timeout"
require "shellwords"
require "raaf/function_tool"

module RAAF
  module Tools
    ##
    # Local Shell Tool - Safe command execution
    #
    # This tool provides controlled access to shell commands with safety features.
    # Unlike ComputerTool which provides full desktop control, this focuses on
    # command-line operations with restrictions.
    #
    # Security features:
    # - Command whitelisting to prevent dangerous operations
    # - Working directory restrictions
    # - Environment variable isolation
    # - Execution timeout protection
    # - Output size limits to prevent memory issues
    # - Protection against directory traversal attacks
    #
    # @example Basic usage
    #   shell = LocalShellTool.new
    #   agent.add_tool(shell)
    #   
    #   # Agent can now execute: ls, cat, grep, etc.
    #
    # @example With custom whitelist
    #   shell = LocalShellTool.new(
    #     allowed_commands: ["ls", "cat", "grep", "find"],
    #     working_dir: "/tmp/safe_dir",
    #     timeout: 10,
    #     max_output: 5000
    #   )
    #
    # @example With environment variables
    #   shell = LocalShellTool.new(
    #     env_vars: { "API_KEY" => "secret" },
    #     allowed_commands: ["curl", "wget"]
    #   )
    #
    class LocalShellTool < FunctionTool
      # Default timeout for command execution in seconds
      DEFAULT_TIMEOUT = 30
      
      # Default maximum output size in characters
      DEFAULT_MAX_OUTPUT = 10_000

      # Default safe commands that can be executed
      # These commands are considered safe for general use
      DEFAULT_ALLOWED_COMMANDS = %w[
        ls cat head tail grep find wc sort uniq cut awk sed
        echo date pwd cd mkdir rmdir touch cp mv
        curl wget git npm yarn python ruby node
        pip gem bundle cargo go
      ].freeze

      # Dangerous commands that are always blocked
      # These commands can cause system damage or security issues
      BLOCKED_COMMANDS = %w[
        rm sudo su chmod chown kill pkill killall
        systemctl service shutdown reboot halt poweroff
        dd mkfs mount umount fdisk parted
        iptables firewall-cmd ufw
      ].freeze

      # @!attribute [r] working_dir
      #   @return [String] Current working directory for command execution
      # @!attribute [r] allowed_commands
      #   @return [Array<String>] List of allowed command names
      attr_reader :working_dir, :allowed_commands

      ##
      # Initialize a new local shell tool
      #
      # @param allowed_commands [Array<String>] Commands that can be executed
      # @param working_dir [String, nil] Working directory (defaults to current dir)
      # @param timeout [Integer] Maximum execution time in seconds
      # @param max_output [Integer] Maximum output size in characters
      # @param env_vars [Hash] Environment variables to set for commands
      # @raise [ArgumentError] if working directory is invalid
      #
      def initialize(allowed_commands: DEFAULT_ALLOWED_COMMANDS,
                     working_dir: nil,
                     timeout: DEFAULT_TIMEOUT,
                     max_output: DEFAULT_MAX_OUTPUT,
                     env_vars: {})
        @allowed_commands = allowed_commands.map(&:to_s)
        @working_dir = working_dir || Dir.pwd
        @timeout = timeout
        @max_output = max_output
        @env_vars = env_vars

        validate_working_dir!

        super(
          method(:execute_command),
          name: "local_shell",
          description: "Execute shell commands in a controlled environment"
        )
      end

      private

      ##
      # Execute a shell command safely
      #
      # @param command [String] The command to execute
      # @param args [Array<String>, nil] Command arguments (optional)
      # @param working_dir [String, nil] Override working directory (optional)
      # @return [Hash] Execution result with stdout, stderr, exit code, etc.
      #
      # @example Execute with parsed command
      #   execute_command(command: "ls -la /tmp")
      #   # => { stdout: "...", stderr: "", exit_code: 0, success: true }
      #
      # @example Execute with separate args
      #   execute_command(command: "grep", args: ["-r", "TODO", "."])
      #
      def execute_command(command:, args: nil, working_dir: nil)
        # Parse command and arguments
        if args.nil?
          # If no args provided, try to parse from command string
          parts = Shellwords.split(command)
          cmd = parts.first
          arguments = parts[1..]
        else
          cmd = command
          arguments = Array(args)
        end

        # Validate command
        validate_command!(cmd)

        # Determine working directory
        cwd = working_dir || @working_dir
        validate_directory!(cwd)

        # Build full command
        full_command = [cmd] + arguments

        # Execute with timeout
        output, error, status = nil

        Timeout.timeout(@timeout) do
          output, error, status = Open3.capture3(
            @env_vars,
            *full_command,
            chdir: cwd,
            unsetenv_others: false
          )
        end

        # Truncate output if needed
        output = truncate_output(output)
        error = truncate_output(error)

        {
          command: full_command.join(" "),
          stdout: output,
          stderr: error,
          exit_code: status.exitstatus,
          success: status.success?,
          working_dir: cwd
        }
      rescue Timeout::Error
        {
          command: full_command&.join(" ") || command,
          error: "Command timed out after #{@timeout} seconds",
          timeout: true
        }
      rescue StandardError => e
        {
          command: full_command&.join(" ") || command,
          error: e.message,
          exception: e.class.name
        }
      end

      ##
      # Validates that a command is safe to execute
      #
      # @param command [String] Command to validate
      # @raise [SecurityError] if command is blocked or not allowed
      # @private
      #
      def validate_command!(command)
        cmd_name = File.basename(command.to_s).split.first

        if BLOCKED_COMMANDS.include?(cmd_name)
          raise SecurityError, "Command '#{cmd_name}' is blocked for security reasons"
        end

        return if @allowed_commands.include?(cmd_name)

        raise SecurityError, "Command '#{cmd_name}' is not in the allowed list"
      end

      ##
      # Validates the working directory exists and is readable
      #
      # @raise [ArgumentError] if directory is invalid
      # @private
      #
      def validate_working_dir!
        raise ArgumentError, "Working directory does not exist: #{@working_dir}" unless Dir.exist?(@working_dir)

        return if File.readable?(@working_dir)

        raise ArgumentError, "Working directory is not readable: #{@working_dir}"
      end

      ##
      # Validates a directory path for security
      #
      # Ensures the directory exists and prevents directory traversal attacks
      # by checking that the path stays within the configured working directory.
      #
      # @param dir [String] Directory path to validate
      # @raise [ArgumentError] if directory doesn't exist
      # @raise [SecurityError] if directory is outside allowed path
      # @private
      #
      def validate_directory!(dir)
        expanded = File.expand_path(dir)

        raise ArgumentError, "Directory does not exist: #{dir}" unless Dir.exist?(expanded)

        # Prevent directory traversal attacks
        return if expanded.start_with?(File.expand_path(@working_dir))

        raise SecurityError, "Directory access outside of working directory not allowed"
      end

      ##
      # Truncates output to prevent memory issues
      #
      # @param text [String, nil] Text to truncate
      # @return [String] Truncated text with indicator if truncated
      # @private
      #
      def truncate_output(text)
        return "" if text.nil?

        if text.length > @max_output
          "#{text[0...@max_output]}\n... (truncated)"
        else
          text
        end
      end

      ##
      # Returns the JSON Schema for function parameters
      #
      # @return [Hash] Parameter schema for OpenAI function calling
      #
      def self.schema
        {
          type: "object",
          properties: {
            command: {
              type: "string",
              description: "The shell command to execute"
            },
            args: {
              type: "array",
              items: { type: "string" },
              description: "Command arguments (optional, can be parsed from command)"
            },
            working_dir: {
              type: "string",
              description: "Working directory for command execution (optional)"
            }
          },
          required: ["command"]
        }
      end
    end

    ##
    # Extended version with more capabilities
    #
    # AdvancedShellTool extends LocalShellTool with additional commands
    # suitable for development and DevOps tasks. It includes support for:
    # - Container tools (docker, kubectl)
    # - Build tools (make, cmake, gcc)
    # - Database clients (psql, mysql, redis-cli)
    # - Network tools (ssh, rsync, curl)
    # - Pipeline execution
    #
    # @example Basic usage
    #   tool = AdvancedShellTool.new
    #   agent.add_tool(tool)
    #
    # @example Pipeline execution
    #   tool.execute_pipeline(
    #     commands: [
    #       ["cat", "data.txt"],
    #       ["grep", "ERROR"],
    #       ["wc", "-l"]
    #     ]
    #   )
    #
    class AdvancedShellTool < LocalShellTool
      ##
      # Initialize an advanced shell tool with extended command set
      #
      # @param options [Hash] Options passed to LocalShellTool
      #
      def initialize(**options)
        # Add more commands for advanced usage
        extended_commands = DEFAULT_ALLOWED_COMMANDS + %w[
          docker docker-compose kubectl helm
          terraform ansible vagrant
          make cmake gcc g++ clang
          psql mysql redis-cli mongo
          jq yq xmllint
          openssl base64 md5sum sha256sum
          tar zip unzip gzip gunzip
          diff patch
          netstat lsof ps top htop
          dig nslookup ping traceroute
          ssh scp rsync
        ]

        options[:allowed_commands] ||= extended_commands
        super
      end

      ##
      # Execute a pipeline of commands
      #
      # Allows chaining multiple commands with pipe operators.
      # Each command in the pipeline is validated for security.
      #
      # @param commands [Array<Array<String>>] Array of command arrays
      # @return [Hash] Execution result
      #
      # @example Count error lines
      #   execute_pipeline(
      #     commands: [
      #       ["cat", "app.log"],
      #       ["grep", "ERROR"],
      #       ["wc", "-l"]
      #     ]
      #   )
      #
      def execute_pipeline(commands:)
        validate_pipeline!(commands)

        # Build pipeline command
        pipeline = commands.map { |cmd| Shellwords.join(cmd) }.join(" | ")

        # Execute as shell command
        execute_command(command: "sh", args: ["-c", pipeline])
      end

      private

      ##
      # Validates all commands in a pipeline
      #
      # @param commands [Array<Array<String>>] Pipeline commands
      # @raise [SecurityError] if any command is not allowed
      # @private
      #
      def validate_pipeline!(commands)
        commands.each do |cmd_parts|
          validate_command!(cmd_parts.first)
        end
      end
    end
  end
end
