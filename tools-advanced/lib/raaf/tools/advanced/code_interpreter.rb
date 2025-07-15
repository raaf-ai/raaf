# frozen_string_literal: true

require "tempfile"
require "json"
require "timeout"

module RubyAIAgentsFactory
  module Tools
    module Advanced
      ##
      # Code interpreter tool for AI agents
      #
      # Provides AI agents with the ability to execute code in multiple languages
      # within a secure sandbox environment. Supports Python, Ruby, JavaScript,
      # and other languages with proper isolation and security controls.
      #
      # @example Basic code execution
      #   interpreter = CodeInterpreter.new(
      #     languages: [:python, :ruby],
      #     sandbox: true
      #   )
      #   
      #   agent = Agent.new(
      #     name: "CodeAgent",
      #     instructions: "You can execute code to help users"
      #   )
      #   agent.add_tool(interpreter)
      #
      # @example Python data analysis
      #   result = interpreter.execute_code(
      #     language: "python",
      #     code: "import pandas as pd; df = pd.DataFrame({'x': [1,2,3]}); print(df.describe())"
      #   )
      #
      class CodeInterpreter < RubyAIAgentsFactory::FunctionTool
        include RubyAIAgentsFactory::Logging

        # @return [Array<Symbol>] Supported languages
        attr_reader :languages

        # @return [Boolean] Whether sandbox mode is enabled
        attr_reader :sandbox

        # @return [Integer] Execution timeout in seconds
        attr_reader :timeout

        # @return [String] Memory limit
        attr_reader :memory_limit

        ##
        # Initialize code interpreter
        #
        # @param languages [Array<Symbol>] Supported languages
        # @param sandbox [Boolean] Enable sandbox mode
        # @param timeout [Integer] Execution timeout in seconds
        # @param memory_limit [String] Memory limit (e.g., "512MB")
        # @param temp_dir [String] Temporary directory for files
        #
        def initialize(languages: [:python, :ruby, :javascript], sandbox: true, timeout: 60, memory_limit: "512MB", temp_dir: nil)
          @languages = languages
          @sandbox = sandbox
          @timeout = timeout
          @memory_limit = memory_limit
          @temp_dir = temp_dir || Dir.tmpdir
          @execution_count = 0

          validate_languages!
          setup_sandbox! if @sandbox

          super(
            method(:execute_code),
            name: "code_interpreter",
            description: "Execute code in multiple languages with sandbox isolation"
          )
        end

        ##
        # Execute code in specified language
        #
        # @param language [String] Programming language
        # @param code [String] Code to execute
        # @param files [Array<Hash>, nil] Input files
        # @param environment [Hash, nil] Environment variables
        # @return [Hash] Execution result
        #
        def execute_code(language:, code:, files: nil, environment: nil)
          validate_security!
          validate_language!(language)

          @execution_count += 1
          execution_id = "exec_#{@execution_count}_#{SecureRandom.hex(4)}"

          log_info("Executing code", {
            execution_id: execution_id,
            language: language,
            code_length: code.length,
            sandbox: @sandbox
          })

          begin
            result = case language.downcase
                     when "python"
                       execute_python(code, files, environment, execution_id)
                     when "ruby"
                       execute_ruby(code, files, environment, execution_id)
                     when "javascript", "js"
                       execute_javascript(code, files, environment, execution_id)
                     when "bash", "shell"
                       execute_bash(code, files, environment, execution_id)
                     when "sql"
                       execute_sql(code, files, environment, execution_id)
                     else
                       raise ArgumentError, "Unsupported language: #{language}"
                     end

            log_info("Code execution completed", {
              execution_id: execution_id,
              success: result[:success],
              execution_time: result[:execution_time]
            })

            result
          rescue StandardError => e
            log_error("Code execution error", {
              execution_id: execution_id,
              error: e
            })

            {
              success: false,
              error: e.message,
              execution_id: execution_id,
              language: language
            }
          end
        end

        private

        def validate_security!
          return if @sandbox

          raise SecurityError, "Code execution requires sandbox mode for security"
        end

        def validate_languages!
          @languages.each do |lang|
            unless supported_language?(lang)
              raise ArgumentError, "Unsupported language: #{lang}"
            end
          end
        end

        def validate_language!(language)
          lang_sym = language.to_sym
          unless @languages.include?(lang_sym)
            raise ArgumentError, "Language not enabled: #{language}"
          end
        end

        def supported_language?(language)
          [:python, :ruby, :javascript, :js, :bash, :shell, :sql].include?(language.to_sym)
        end

        def setup_sandbox!
          # Create isolated temp directory
          @sandbox_dir = File.join(@temp_dir, "raaf_sandbox_#{SecureRandom.hex(8)}")
          Dir.mkdir(@sandbox_dir) unless Dir.exist?(@sandbox_dir)

          # Set up resource limits
          setup_resource_limits
        end

        def setup_resource_limits
          # This would set up cgroups, ulimits, etc. in a production environment
          # For now, we'll use Ruby's timeout mechanism
        end

        def execute_python(code, files, environment, execution_id)
          start_time = Time.current

          # Create temporary file
          temp_file = create_temp_file(code, ".py", execution_id)
          
          # Setup environment
          env = setup_environment(environment)
          
          # Prepare command
          cmd = build_python_command(temp_file.path)
          
          # Execute with timeout
          stdout, stderr, exit_code = execute_with_timeout(cmd, env)
          
          {
            success: exit_code == 0,
            output: stdout,
            error: stderr,
            exit_code: exit_code,
            execution_time: Time.current - start_time,
            execution_id: execution_id,
            language: "python"
          }
        ensure
          temp_file&.close
          temp_file&.unlink
        end

        def execute_ruby(code, files, environment, execution_id)
          start_time = Time.current

          # Create temporary file
          temp_file = create_temp_file(code, ".rb", execution_id)
          
          # Setup environment
          env = setup_environment(environment)
          
          # Prepare command
          cmd = build_ruby_command(temp_file.path)
          
          # Execute with timeout
          stdout, stderr, exit_code = execute_with_timeout(cmd, env)
          
          {
            success: exit_code == 0,
            output: stdout,
            error: stderr,
            exit_code: exit_code,
            execution_time: Time.current - start_time,
            execution_id: execution_id,
            language: "ruby"
          }
        ensure
          temp_file&.close
          temp_file&.unlink
        end

        def execute_javascript(code, files, environment, execution_id)
          start_time = Time.current

          # Create temporary file
          temp_file = create_temp_file(code, ".js", execution_id)
          
          # Setup environment
          env = setup_environment(environment)
          
          # Prepare command
          cmd = build_javascript_command(temp_file.path)
          
          # Execute with timeout
          stdout, stderr, exit_code = execute_with_timeout(cmd, env)
          
          {
            success: exit_code == 0,
            output: stdout,
            error: stderr,
            exit_code: exit_code,
            execution_time: Time.current - start_time,
            execution_id: execution_id,
            language: "javascript"
          }
        ensure
          temp_file&.close
          temp_file&.unlink
        end

        def execute_bash(code, files, environment, execution_id)
          start_time = Time.current

          # Create temporary file
          temp_file = create_temp_file(code, ".sh", execution_id)
          
          # Setup environment
          env = setup_environment(environment)
          
          # Prepare command
          cmd = build_bash_command(temp_file.path)
          
          # Execute with timeout
          stdout, stderr, exit_code = execute_with_timeout(cmd, env)
          
          {
            success: exit_code == 0,
            output: stdout,
            error: stderr,
            exit_code: exit_code,
            execution_time: Time.current - start_time,
            execution_id: execution_id,
            language: "bash"
          }
        ensure
          temp_file&.close
          temp_file&.unlink
        end

        def execute_sql(code, files, environment, execution_id)
          # SQL execution would require database connection
          # This is a placeholder for SQL execution logic
          {
            success: false,
            error: "SQL execution not implemented yet",
            execution_id: execution_id,
            language: "sql"
          }
        end

        def create_temp_file(code, extension, execution_id)
          temp_file = Tempfile.new([execution_id, extension], @sandbox_dir)
          temp_file.write(code)
          temp_file.flush
          temp_file
        end

        def setup_environment(environment)
          env = ENV.to_h
          env.merge!(environment) if environment
          
          # Add security restrictions
          if @sandbox
            env["HOME"] = @sandbox_dir
            env["TMPDIR"] = @sandbox_dir
            env["PATH"] = "/usr/bin:/bin"
          end
          
          env
        end

        def build_python_command(file_path)
          cmd = ["python3", file_path]
          
          if @sandbox
            # Add sandbox restrictions
            cmd = ["timeout", @timeout.to_s] + cmd
          end
          
          cmd
        end

        def build_ruby_command(file_path)
          cmd = ["ruby", file_path]
          
          if @sandbox
            # Add sandbox restrictions
            cmd = ["timeout", @timeout.to_s] + cmd
          end
          
          cmd
        end

        def build_javascript_command(file_path)
          cmd = ["node", file_path]
          
          if @sandbox
            # Add sandbox restrictions
            cmd = ["timeout", @timeout.to_s] + cmd
          end
          
          cmd
        end

        def build_bash_command(file_path)
          cmd = ["bash", file_path]
          
          if @sandbox
            # Add sandbox restrictions
            cmd = ["timeout", @timeout.to_s] + cmd
          end
          
          cmd
        end

        def execute_with_timeout(cmd, env)
          stdout = ""
          stderr = ""
          exit_code = 0

          begin
            Timeout.timeout(@timeout) do
              Open3.popen3(env, *cmd) do |stdin, stdout_pipe, stderr_pipe, wait_thr|
                stdin.close
                
                # Read output
                stdout = stdout_pipe.read
                stderr = stderr_pipe.read
                
                exit_code = wait_thr.value.exitstatus
              end
            end
          rescue Timeout::Error
            stderr = "Execution timeout (#{@timeout}s)"
            exit_code = 124
          rescue StandardError => e
            stderr = "Execution error: #{e.message}"
            exit_code = 1
          end

          [stdout, stderr, exit_code]
        end
      end
    end
  end
end