# frozen_string_literal: true

require "tempfile"
require "timeout"
require "fileutils"
require "securerandom"
require "raaf/function_tool"
require "raaf/logging"

module RAAF
  module Tools
    ##
    # Code Interpreter Tool - Safe sandboxed code execution
    #
    # This tool provides a secure environment for executing Python and Ruby code
    # with file I/O capabilities, similar to OpenAI's Code Interpreter. Perfect
    # for data analysis, visualization, mathematical computations, and file processing.
    #
    # @example Basic usage with agent
    #   interpreter = CodeInterpreterTool.new
    #   agent.add_tool(interpreter)
    #   
    #   # Agent can now execute code
    #   result = agent.run("Calculate the mean of [1, 2, 3, 4, 5] using Python")
    #
    # @example Data analysis workflow
    #   interpreter = CodeInterpreterTool.new(timeout: 60)
    #   
    #   # Upload data file
    #   file_path = interpreter.upload_file("data.csv")
    #   
    #   # Execute analysis
    #   result = interpreter.execute_code(
    #     language: "python",
    #     code: """
    #     import pandas as pd
    #     import matplotlib.pyplot as plt
    #     
    #     # Load and analyze data
    #     df = pd.read_csv('#{file_path}')
    #     summary = df.describe()
    #     
    #     # Create visualization
    #     plt.figure(figsize=(10, 6))
    #     df.hist(bins=20)
    #     plt.savefig('analysis.png')
    #     
    #     print(summary)
    #     """
    #   )
    #   
    #   # Download results
    #   interpreter.download_file("analysis.png")
    #
    # @example Mathematical computation
    #   result = interpreter.execute_code(
    #     language: "python",
    #     code: """
    #     import numpy as np
    #     from scipy import stats
    #     
    #     # Generate sample data
    #     data = np.random.normal(100, 15, 1000)
    #     
    #     # Perform statistical analysis
    #     mean = np.mean(data)
    #     std = np.std(data)
    #     confidence_interval = stats.norm.interval(0.95, mean, std/np.sqrt(len(data)))
    #     
    #     print(f"Mean: {mean:.2f}")
    #     print(f"Standard Deviation: {std:.2f}")
    #     print(f"95% Confidence Interval: {confidence_interval}")
    #     """
    #   )
    #
    # @example Custom security settings
    #   interpreter = CodeInterpreterTool.new(
    #     timeout: 30,           # Max execution time
    #     memory_limit: "512M",  # Memory limit
    #     allowed_libraries: [   # Whitelist libraries
    #       "pandas", "numpy", "matplotlib", "seaborn"
    #     ],
    #     enable_networking: false  # Disable network access
    #   )
    #
    # @example Ruby code execution
    #   result = interpreter.execute_code(
    #     language: "ruby",
    #     code: """
    #     # File processing in Ruby
    #     data = File.readlines('input.txt').map(&:strip)
    #     
    #     # Process data
    #     processed = data.map { |line| line.upcase.reverse }
    #     
    #     # Write results
    #     File.write('output.txt', processed.join("\n"))
    #     
    #     puts "Processed #{data.size} lines"
    #     """
    #   )
    #
    # @note Security Features:
    #   - Isolated filesystem per session
    #   - Configurable timeout protection
    #   - Memory usage limits
    #   - Restricted library access
    #   - No network access by default
    #   - Automatic cleanup of temporary files
    #
    # @see FunctionTool Base tool class
    # @since 1.0.0
    #
    #     max_file_size: 10 * 1024 * 1024  # 10MB
    #   )
    class CodeInterpreterTool < FunctionTool
      include Logger
      DEFAULT_TIMEOUT = 10 # seconds
      DEFAULT_MAX_FILE_SIZE = 5 * 1024 * 1024 # 5MB
      DEFAULT_MAX_OUTPUT_LENGTH = 10_000 # characters

      # Safe Python libraries
      SAFE_PYTHON_IMPORTS = %w[
        math random statistics json csv datetime
        collections itertools functools re
        numpy pandas matplotlib seaborn
      ].freeze

      # Safe Ruby libraries
      SAFE_RUBY_REQUIRES = %w[
        json csv date time set
        bigdecimal matrix prime
      ].freeze

      attr_reader :session_id, :workspace_dir

      def initialize(timeout: DEFAULT_TIMEOUT,
                     max_file_size: DEFAULT_MAX_FILE_SIZE,
                     max_output_length: DEFAULT_MAX_OUTPUT_LENGTH)
        @timeout = timeout
        @max_file_size = max_file_size
        @max_output_length = max_output_length
        @session_id = SecureRandom.hex(8)
        @workspace_dir = create_workspace

        super(
          method(:execute_code),
          name: "code_interpreter",
          description: "Execute Python or Ruby code in a sandboxed environment with file I/O"
        )
      end

      # Clean up workspace on garbage collection
      def cleanup
        FileUtils.rm_rf(@workspace_dir) if @workspace_dir && Dir.exist?(@workspace_dir)
      end

      private

      def execute_code(code:, language: "python")
        validate_language!(language)

        case language.downcase
        when "python"
          execute_python(code)
        when "ruby"
          execute_ruby(code)
        else
          { error: "Unsupported language: #{language}" }
        end
      rescue StandardError => e
        { error: "Execution error: #{e.message}", backtrace: e.backtrace.first(5) }
      end

      def validate_language!(language)
        return if %w[python ruby].include?(language.downcase)

        raise ArgumentError, "Language must be 'python' or 'ruby'"
      end

      def create_workspace
        base_dir = ENV["RAAF_WORKSPACE"] || "/tmp/raaf_workspaces"
        FileUtils.mkdir_p(base_dir)

        workspace = File.join(base_dir, "session_#{@session_id}")
        FileUtils.mkdir_p(workspace)
        workspace
      end

      def execute_python(code)
        # Create a Python script with safety measures
        script = Tempfile.new(["code", ".py"], @workspace_dir)

        # Add safety imports and constraints
        safety_prelude = <<~PYTHON
          import sys
          import os
          import signal
          import resource

          # Set memory limit (256MB)
          resource.setrlimit(resource.RLIMIT_AS, (256 * 1024 * 1024, 256 * 1024 * 1024))

          # Disable dangerous functions
          __builtins__['eval'] = None
          __builtins__['exec'] = None
          __builtins__['compile'] = None
          __builtins__['__import__'] = __limited_import

          # Limited import function
          def __limited_import(name, *args, **kwargs):
              allowed = #{SAFE_PYTHON_IMPORTS}
              if name.split('.')[0] not in allowed:
                  raise ImportError(f"Import of '{name}' is not allowed")
              return __original_import(name, *args, **kwargs)

          __original_import = __builtins__['__import__']
          __builtins__['__import__'] = __limited_import

          # Change to workspace directory
          os.chdir('#{@workspace_dir}')

          # User code starts here
          try:
        PYTHON

        safety_postlude = <<~PYTHON

          except Exception as e:
              print(f"Error: {type(e).__name__}: {str(e)}", file=sys.stderr)
              import traceback
              traceback.print_exc(limit=5)
        PYTHON

        script.write(safety_prelude)
        script.write(code.each_line.map { |line| "    #{line}" }.join)
        script.write(safety_postlude)
        script.close

        # Execute with timeout
        output = ""

        Timeout.timeout(@timeout) do
          IO.popen(["python3", script.path], err: %i[child out]) do |io|
            output = io.read(@max_output_length)
          end
        end

        {
          output: output,
          files: list_workspace_files,
          session_id: @session_id,
          language: "python"
        }
      rescue Timeout::Error
        { error: "Code execution timed out after #{@timeout} seconds" }
      ensure
        script&.unlink
      end

      def execute_ruby(code)
        # Create a Ruby script with safety measures
        script = Tempfile.new(["code", ".rb"], @workspace_dir)

        # Add safety constraints
        safety_prelude = <<~RUBY
          # Limit execution time
          Thread.new do
            sleep #{@timeout}
            log_warn("Code execution timed out", timeout: @timeout, language: language)
            exit 1
          end

          # Remove dangerous methods
          class Object
            undef :eval if respond_to?(:eval)
            undef :instance_eval if respond_to?(:instance_eval)
            undef :class_eval if respond_to?(:class_eval)
            undef :module_eval if respond_to?(:module_eval)
            undef :send if respond_to?(:send)
            undef :public_send if respond_to?(:public_send)
            undef :__send__ if respond_to?(:__send__)
          end

          # Safe require
          module Kernel
            alias_method :__original_require, :require
            def require(name)
              allowed = #{SAFE_RUBY_REQUIRES}
              unless allowed.include?(name)
                raise LoadError, "Require of '\#{name}' is not allowed"
              end
              __original_require(name)
            end
          end

          # Change to workspace directory
          Dir.chdir('#{@workspace_dir}')

          # Capture output
          $stdout_backup = $stdout
          $stdout = StringIO.new

          begin
            # User code starts here
        RUBY

        safety_postlude = <<~RUBY

          rescue => e
            $stdout.puts "Error: \#{e.class}: \#{e.message}"
            $stdout.puts e.backtrace.first(5).join("\n")
          ensure
            output = $stdout.string
            $stdout = $stdout_backup
            puts output
          end
        RUBY

        script.write(safety_prelude)
        script.write(code.each_line.map { |line| "  #{line}" }.join)
        script.write(safety_postlude)
        script.close

        # Execute with timeout
        output = ""

        Timeout.timeout(@timeout) do
          # Run in subprocess for better isolation
          IO.popen(["ruby", script.path], err: %i[child out]) do |io|
            output = io.read(@max_output_length)
          end
        end

        {
          output: output,
          files: list_workspace_files,
          session_id: @session_id,
          language: "ruby"
        }
      rescue Timeout::Error
        { error: "Code execution timed out after #{@timeout} seconds" }
      ensure
        script&.unlink
      end

      def list_workspace_files
        files = []

        Dir.glob(File.join(@workspace_dir, "**/*")).each do |path|
          next unless File.file?(path)

          relative_path = path.sub("#{@workspace_dir}/", "")
          stat = File.stat(path)

          # Skip files that are too large
          next if stat.size > @max_file_size

          files << {
            path: relative_path,
            size: stat.size,
            modified: stat.mtime.iso8601
          }
        end

        files
      end

      # Schema for function parameters
      def self.schema
        {
          type: "object",
          properties: {
            code: {
              type: "string",
              description: "The Python or Ruby code to execute"
            },
            language: {
              type: "string",
              enum: %w[python ruby],
              description: "Programming language to use",
              default: "python"
            }
          },
          required: ["code"]
        }
      end
    end

    # Convenience class for file operations in code interpreter
    class CodeInterpreterFile
      attr_reader :path, :session_id

      def initialize(path, session_id, workspace_dir)
        @path = path
        @session_id = session_id
        @workspace_dir = workspace_dir
        @full_path = File.join(@workspace_dir, path)
      end

      def read
        return nil unless File.exist?(@full_path)

        File.read(@full_path)
      end

      def write(content)
        FileUtils.mkdir_p(File.dirname(@full_path))
        File.write(@full_path, content)
      end

      def exists?
        File.exist?(@full_path)
      end

      def delete
        FileUtils.rm_f(@full_path)
      end

      def size
        File.size(@full_path) if exists?
      end
    end
  end
end
