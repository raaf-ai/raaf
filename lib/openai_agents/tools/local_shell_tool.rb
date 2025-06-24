# frozen_string_literal: true

require "open3"
require "timeout"
require "shellwords"
require_relative "../function_tool"

module OpenAIAgents
  module Tools
    # Local Shell Tool - Safe command execution
    #
    # This tool provides controlled access to shell commands with safety features.
    # Unlike ComputerTool which provides full desktop control, this focuses on
    # command-line operations with restrictions.
    #
    # Features:
    # - Whitelisted commands only
    # - Working directory management
    # - Environment variable control
    # - Timeout protection
    # - Output size limits
    #
    # @example Basic usage
    #   shell = LocalShellTool.new
    #   agent.add_tool(shell)
    #
    # @example With custom whitelist
    #   shell = LocalShellTool.new(
    #     allowed_commands: ["ls", "cat", "grep", "find"],
    #     working_dir: "/tmp/safe_dir"
    #   )
    class LocalShellTool < FunctionTool
      DEFAULT_TIMEOUT = 30 # seconds
      DEFAULT_MAX_OUTPUT = 10_000 # characters

      # Default safe commands
      DEFAULT_ALLOWED_COMMANDS = %w[
        ls cat head tail grep find wc sort uniq cut awk sed
        echo date pwd cd mkdir rmdir touch cp mv
        curl wget git npm yarn python ruby node
        pip gem bundle cargo go
      ].freeze

      # Dangerous commands that are always blocked
      BLOCKED_COMMANDS = %w[
        rm sudo su chmod chown kill pkill killall
        systemctl service shutdown reboot halt poweroff
        dd mkfs mount umount fdisk parted
        iptables firewall-cmd ufw
      ].freeze

      attr_reader :working_dir, :allowed_commands

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

      def validate_command!(command)
        cmd_name = File.basename(command.to_s).split.first

        if BLOCKED_COMMANDS.include?(cmd_name)
          raise SecurityError, "Command '#{cmd_name}' is blocked for security reasons"
        end

        return if @allowed_commands.include?(cmd_name)

        raise SecurityError, "Command '#{cmd_name}' is not in the allowed list"
      end

      def validate_working_dir!
        raise ArgumentError, "Working directory does not exist: #{@working_dir}" unless Dir.exist?(@working_dir)

        return if File.readable?(@working_dir)

        raise ArgumentError, "Working directory is not readable: #{@working_dir}"
      end

      def validate_directory!(dir)
        expanded = File.expand_path(dir)

        raise ArgumentError, "Directory does not exist: #{dir}" unless Dir.exist?(expanded)

        # Prevent directory traversal attacks
        return if expanded.start_with?(File.expand_path(@working_dir))

        raise SecurityError, "Directory access outside of working directory not allowed"
      end

      def truncate_output(text)
        return "" if text.nil?

        if text.length > @max_output
          "#{text[0...@max_output]}\n... (truncated)"
        else
          text
        end
      end

      # Schema for function parameters
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

    # Extended version with more capabilities
    class AdvancedShellTool < LocalShellTool
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

      # Add pipe support
      def execute_pipeline(commands:)
        validate_pipeline!(commands)

        # Build pipeline command
        pipeline = commands.map { |cmd| Shellwords.join(cmd) }.join(" | ")

        # Execute as shell command
        execute_command(command: "sh", args: ["-c", pipeline])
      end

      private

      def validate_pipeline!(commands)
        commands.each do |cmd_parts|
          validate_command!(cmd_parts.first)
        end
      end
    end
  end
end
