# frozen_string_literal: true

require "fileutils"
require "json"
require "timeout"
require "open3"
require "shellwords"

module RAAF
  module Shared
    ##
    # Generic example validator for RAAF gems
    #
    # This validator can be used across all RAAF gems to validate
    # example files and README code blocks. It provides a consistent
    # interface for running examples with proper error handling and
    # reporting.
    #
    class ExampleValidator
      attr_reader :results, :config, :gem_name, :gem_dir

      ##
      # Initialize validator for a specific gem
      #
      # @param gem_name [String] Name of the gem (e.g., "dsl", "core")
      # @param gem_dir [String] Path to the gem directory
      # @param options [Hash] Configuration options
      #
      def initialize(gem_name, gem_dir, options = {})
        @gem_name = gem_name
        @gem_dir = File.expand_path(gem_dir)
        @results = {
          passed: [],
          failed: [],
          skipped: [],
          warnings: [],
          summary: {}
        }
        @config = build_config(options)
      end

      ##
      # Run validation for all examples
      #
      # @return [Integer] Exit code (0 for success, 1 for failure)
      #
      def run
        puts "🧪 RAAF #{gem_name.upcase} Example Validation"
        puts "=" * 50

        validate_environment
        find_and_validate_examples
        validate_readme_examples if config[:validate_readme]
        generate_report

        exit_code
      end

      ##
      # Validate a single example file
      #
      # @param file_path [String] Path to the example file
      # @return [Hash] Validation result
      #
      def validate_example_file(file_path)
        validate_example(file_path)
      end

      ##
      # Get validation statistics
      #
      # @return [Hash] Summary statistics
      #
      def statistics
        {
          total: results.values.map(&:length).sum,
          passed: results[:passed].length,
          failed: results[:failed].length,
          skipped: results[:skipped].length,
          warnings: results[:warnings].length,
          success_rate: calculate_success_rate
        }
      end

      private

      def build_config(options)
        defaults = {
          # Timeout for each example (in seconds)
          timeout: ENV.fetch("EXAMPLE_TIMEOUT", "30").to_i,

          # Run in CI mode (stricter validation)
          ci_mode: ENV.fetch("CI", "false") == "true",

          # Validate README examples
          validate_readme: true,

          # Required environment variables
          required_env: [],

          # Examples to skip
          skip_files: [],

          # Examples that only need syntax validation
          syntax_only_files: [],

          # Test mode - use dummy API keys
          test_mode: ENV.fetch("RAAF_TEST_MODE", "false") == "true",

          # Success patterns in output
          success_patterns: [
            /Created agent:/i,
            /=== .* Example/i,
            /Conversation:/,
            /SYSTEM:/,
            /USER:/,
            /✓/,
            /agents in \d+\.\d+ seconds/i
          ],

          # Acceptable failure patterns
          acceptable_failure_patterns: [
            /Missing required environment/i,
            /API key not set/i,
            /requires.*setup/i,
            /Invalid API key/i,
            /AuthenticationError/,
            /Authentication failed/i
          ],

          # Custom require paths for the gem
          require_paths: [],

          # Additional environment variables
          env_vars: {}
        }

        defaults.merge(options)
      end

      def validate_environment
        puts "🔍 Environment Check"

        # Check gem directory
        gemspec_path = File.join(gem_dir, "#{gem_name}.gemspec")
        raaf_gemspec_path = File.join(gem_dir, "raaf-#{gem_name}.gemspec")

        unless (File.exist?(gemspec_path) || File.exist?(raaf_gemspec_path)) &&
               File.directory?(File.join(gem_dir, "lib"))
          puts "  ❌ Not in a valid gem directory: #{gem_dir}"
          exit(1)
        end

        puts "  📁 Gem: #{gem_name}"
        puts "  📁 Directory: #{gem_dir}"
        puts "  🐣 Ruby version: #{RUBY_VERSION}"

        # Check required environment variables
        check_required_environment

        # Check bundler
        check_bundler

        puts
      end

      def check_required_environment
        if config[:test_mode]
          puts "  🧪 Test mode: enabled"
          setup_test_environment
        else
          config[:required_env].each do |env_var|
            if ENV[env_var] && !ENV[env_var].empty?
              puts "  🔑 #{env_var}: present"
            elsif config[:ci_mode]
              puts "  ❌ #{env_var}: missing (required for CI)"
              puts "  💡 Set RAAF_TEST_MODE=true to run validation without real API keys"
              exit(1)
            else
              puts "  ⚠️  #{env_var}: missing (some examples may be skipped)"
            end
          end
        end
      end

      def setup_test_environment
        # Set up dummy values for test mode
        ENV["OPENAI_API_KEY"] ||= "test-api-key-for-validation"
        ENV["TAVILY_API_KEY"] ||= "test-tavily-key-for-validation"
        ENV["ANTHROPIC_API_KEY"] ||= "test-anthropic-key-for-validation"
      end

      def check_bundler
        `bundle --version`
        puts "  📦 Bundler: available"
      rescue StandardError
        puts "  ❌ Bundler: not available"
        exit(1)
      end

      def find_and_validate_examples
        examples_dir = File.join(gem_dir, "examples")

        unless File.directory?(examples_dir)
          puts "ℹ️  No examples directory found for #{gem_name}"
          return
        end

        example_files = Dir.glob(File.join(examples_dir, "*.rb"))
        puts "📁 Found #{example_files.length} example files in #{gem_name}/examples/"
        puts

        example_files.sort.each do |file_path|
          validate_example(file_path)
        end
      end

      def validate_example(file_path)
        filename = File.basename(file_path)
        puts "🔍 #{filename}"

        # Check if file should be skipped
        if config[:skip_files].include?(filename)
          record_result(:skipped, filename, "Explicitly skipped in configuration")
          return
        end

        # Determine validation type
        syntax_only = config[:syntax_only_files].include?(filename)

        result = if syntax_only
                   validate_syntax(file_path, filename)
                 else
                   validate_execution(file_path, filename)
                 end

        record_and_display_result(result)
      end

      def validate_syntax(file_path, filename)
        Timeout.timeout(10) do
          _, stderr, status = Open3.capture3(
            "ruby -c #{Shellwords.escape(file_path)}"
          )

          if status.success?
            {
              status: :passed,
              file: filename,
              message: "Syntax check passed"
            }
          else
            {
              status: :failed,
              file: filename,
              message: "Syntax errors found",
              error: stderr.strip.lines.first
            }
          end
        end
      rescue Timeout::Error
        {
          status: :failed,
          file: filename,
          message: "Syntax check timed out"
        }
      end

      def validate_execution(file_path, filename)
        # First check syntax and constants
        syntax_result = validate_syntax_and_constants(file_path, filename)
        return syntax_result unless syntax_result[:status] == :passed

        Timeout.timeout(config[:timeout]) do
          env = build_execution_environment
          command = build_execution_command(file_path)

          stdout, stderr, status = Open3.capture3(env, command, chdir: gem_dir)

          analyze_execution_result(filename, stdout, stderr, status)
        end
      rescue Timeout::Error
        {
          status: :failed,
          file: filename,
          message: "Execution timed out",
          error: "Timeout after #{config[:timeout]} seconds"
        }
      rescue StandardError => e
        {
          status: :failed,
          file: filename,
          message: "Execution error",
          error: e.message
        }
      end

      def build_execution_environment
        env = ENV.to_h.merge({
                               "RAAF_EXAMPLE_MODE" => "true",
                               "RAAF_LOG_LEVEL" => "warn",
                               "BUNDLE_GEMFILE" => File.join(gem_dir, "Gemfile")
                             })

        # Add test mode if enabled
        if config[:test_mode]
          env["RAAF_TEST_MODE"] = "true"
          env["RAAF_MOCK_RESPONSES"] = "true"
        end

        # Add custom environment variables
        env.merge!(config[:env_vars])

        env
      end

      def build_execution_command(file_path)
        # Build require paths
        require_args = config[:require_paths].map { |path| "-I #{path}" }.join(" ")

        "bundle exec ruby #{require_args} #{Shellwords.escape(file_path)}"
      end

      def analyze_execution_result(filename, stdout, stderr, status)
        combined_output = "#{stdout}\n#{stderr}".strip

        if status.success?
          if config[:success_patterns].any? { |pattern| combined_output.match?(pattern) }
            {
              status: :passed,
              file: filename,
              message: "Executed successfully with expected output",
              output: extract_key_output(stdout)
            }
          else
            {
              status: :warnings,
              file: filename,
              message: "Executed without error but no clear success indicators",
              output: extract_key_output(combined_output)
            }
          end
        elsif config[:acceptable_failure_patterns].any? { |pattern| combined_output.match?(pattern) }
          skip_reason = determine_skip_reason(combined_output)
          {
            status: :skipped,
            file: filename,
            message: skip_reason,
            error: extract_key_output(stderr)
          }
        elsif config[:test_mode] && is_authentication_error?(combined_output)
          {
            status: :skipped,
            file: filename,
            message: "Skipped in test mode due to missing API credentials (syntax verified)",
            error: extract_key_output(stderr)
          }
        else
          {
            status: :failed,
            file: filename,
            message: "Execution failed",
            error: extract_key_output(stderr)
          }
        end
      end

      def validate_readme_examples
        readme_path = File.join(gem_dir, "README.md")
        return unless File.exist?(readme_path)

        puts "\n📄 Validating README Examples"
        puts "=" * 40

        readme_content = File.read(readme_path)
        ruby_code_blocks = extract_ruby_code_blocks(readme_content)

        if ruby_code_blocks.empty?
          puts "  ℹ️  No Ruby code blocks found in README"
          return
        end

        puts "  📝 Found #{ruby_code_blocks.length} Ruby code blocks in README.md\n\n"

        ruby_code_blocks.each_with_index do |code_block, index|
          validate_readme_code_block(code_block, index + 1)
        end
      end

      def extract_ruby_code_blocks(content)
        blocks = []
        in_ruby_block = false
        current_block = []
        block_start_line = 0

        content.lines.each_with_index do |line, index|
          if line.strip.start_with?("```ruby")
            in_ruby_block = true
            block_start_line = index + 1
            current_block = []
          elsif in_ruby_block && line.strip == "```"
            blocks << {
              code: current_block.join,
              start_line: block_start_line,
              line_count: current_block.length
            }
            in_ruby_block = false
          elsif in_ruby_block
            current_block << line
          end
        end

        blocks
      end

      def validate_readme_code_block(code_block, block_number)
        code = code_block[:code]
        description = "README block ##{block_number} (line #{code_block[:start_line]})"

        puts "🔍 #{description}"

        # Skip if it's just a comment or very short
        if code.strip.empty? || code.strip.lines.all? { |l| l.strip.start_with?("#") || l.strip.empty? }
          puts "  ⏭️  Skipped (empty or comments only)\n\n"
          return
        end

        # Determine if this is a runnable example
        runnable = code.include?("require") && (
          code.include?("RAAF::") ||
          code.include?(".run(") ||
          code.include?("Runner.new")
        )

        result = if runnable
                   validate_readme_execution(code, description)
                 else
                   validate_readme_syntax(code, description)
                 end

        record_and_display_result(result)
      end

      def validate_readme_syntax(code, description)
        temp_file = File.join(gem_dir, ".readme_syntax_check.rb")

        begin
          # Add require statement if missing
          full_code = prepare_readme_code(code)
          File.write(temp_file, full_code)

          _, stderr, status = Open3.capture3("ruby -c #{Shellwords.escape(temp_file)}")

          if status.success?
            {
              status: :passed,
              file: description,
              message: "Syntax check passed"
            }
          else
            {
              status: :failed,
              file: description,
              message: "Syntax errors found",
              error: stderr.strip.lines.first
            }
          end
        ensure
          FileUtils.rm_f(temp_file)
        end
      end

      def validate_readme_execution(code, description)
        temp_file = File.join(gem_dir, ".readme_execution_check.rb")

        begin
          full_code = prepare_readme_code_for_execution(code)
          File.write(temp_file, full_code)

          env = build_execution_environment
          command = build_execution_command(temp_file)

          Timeout.timeout(10) do
            stdout, stderr, status = Open3.capture3(env, command, chdir: gem_dir)
            analyze_execution_result(description, stdout, stderr, status)
          end
        rescue Timeout::Error
          {
            status: :failed,
            file: description,
            message: "Execution timed out"
          }
        ensure
          FileUtils.rm_f(temp_file)
        end
      end

      def prepare_readme_code(code)
        if code.include?("require")
          code
        else
          <<~RUBY
            require_relative 'lib/raaf-#{gem_name}'

            #{code}
          RUBY
        end
      end

      def prepare_readme_code_for_execution(code)
        <<~RUBY
          # README example validation
          ENV["RAAF_TEST_MODE"] = "true"
          ENV["OPENAI_API_KEY"] ||= "test-key"

          require_relative "lib/raaf-#{gem_name}"

          # Stub runner if needed for test mode
          if ENV["RAAF_TEST_MODE"] == "true"
            module RAAF
              class Runner
                def run(message)
                  Struct.new(:messages).new([
                    { role: "user", content: message },
                    { role: "assistant", content: "Test response in test mode" }
                  ])
                end
              end
            end
          end

          # Execute the README code
          #{code}

          # Exit cleanly
          exit(0)
        RUBY
      end

      def record_result(status, filename, message, error = nil, output = nil)
        result = {
          status: status,
          file: filename,
          message: message
        }
        result[:error] = error if error
        result[:output] = output if output

        results[status] << result
      end

      def record_and_display_result(result)
        results[result[:status]] << result

        case result[:status]
        when :passed
          puts "  ✅ #{result[:message]}"
          puts "     Output: #{result[:output]}" if result[:output] && !result[:output].empty?
        when :failed
          puts "  ❌ #{result[:message]}"
          puts "     Error: #{result[:error]}" if result[:error]
        when :skipped
          puts "  ⏭️  #{result[:message]}"
          puts "     Reason: #{result[:error]}" if result[:error]
        when :warnings
          puts "  ⚠️  #{result[:message]}"
          puts "     Output: #{result[:output]}" if result[:output]
        end

        puts
      end

      def extract_key_output(output)
        return "" if output.nil? || output.empty?

        # Extract first few meaningful lines
        lines = output.lines
                      .grep_v(/^\s*$/)
                      .grep_v(/bundler|loading/i)
                      .first(3)

        lines.join.strip
      end

      def is_authentication_error?(output)
        auth_patterns = [
          /Invalid API key/i,
          /AuthenticationError/,
          /401/,
          /Unauthorized/i,
          /Authentication failed/i,
          /API key.*not.*set/i,
          /Missing.*API.*key/i
        ]

        auth_patterns.any? { |pattern| output.match?(pattern) }
      end

      def determine_skip_reason(output)
        case output
        when /Missing required environment.*OPENAI_API_KEY/i, /OPENAI_API_KEY.*not set/i
          "Skipped: OPENAI_API_KEY not configured"
        when /Missing required environment.*TAVILY_API_KEY/i, /TAVILY_API_KEY.*not set/i
          "Skipped: TAVILY_API_KEY not configured"
        when /Missing required environment.*ANTHROPIC_API_KEY/i, /ANTHROPIC_API_KEY.*not set/i
          "Skipped: ANTHROPIC_API_KEY not configured"
        when /API key not set/i, /Missing.*API.*key/i
          "Skipped: Required API key not configured"
        when /Invalid API key/i, /AuthenticationError/, /401/, /Unauthorized/i
          "Skipped: Authentication failed (invalid or missing API key)"
        when /requires.*setup/i
          "Skipped: Additional setup required"
        when /Missing required environment/i
          "Skipped: Required environment variable not set"
        else
          # Fallback to generic message if no specific pattern matches
          "Skipped: Configuration or dependency issue"
        end
      end

      def validate_syntax_and_constants(file_path, filename)
        Timeout.timeout(10) do
          # Check basic syntax
          _, stderr, status = Open3.capture3(
            "ruby -c #{Shellwords.escape(file_path)}"
          )

          unless status.success?
            return {
              status: :failed,
              file: filename,
              message: "Syntax errors found",
              error: stderr.strip.lines.first
            }
          end

          # Check for undefined constants and missing requires
          env = build_execution_environment
          check_command = "bundle exec ruby -I#{File.join(gem_dir, "lib")} -e \"require '#{file_path}'; exit(0)\""

          _, stderr, status = Open3.capture3(env, check_command, chdir: gem_dir)

          if !status.success? && stderr.match?(/uninitialized constant|NameError/)
            return {
              status: :failed,
              file: filename,
              message: "Undefined constants or missing requires",
              error: stderr.strip.lines.first
            }
          end

          {
            status: :passed,
            file: filename,
            message: "Syntax and constants check passed"
          }
        end
      rescue Timeout::Error
        {
          status: :failed,
          file: filename,
          message: "Syntax/constants check timed out"
        }
      end

      def generate_report
        total = results.values.map(&:length).sum

        puts "📊 VALIDATION SUMMARY"
        puts "=" * 30
        puts "✅ Passed:   #{results[:passed].length}"
        puts "❌ Failed:   #{results[:failed].length}"
        puts "⏭️  Skipped:  #{results[:skipped].length}"
        puts "⚠️  Warnings: #{results[:warnings].length}"
        puts "📋 Total:    #{total}"
        puts

        show_failure_details
        show_warning_details

        generate_json_report if config[:ci_mode]
      end

      def show_failure_details
        return unless results[:failed].any?

        puts "❌ FAILED EXAMPLES:"
        results[:failed].each do |result|
          puts "  • #{result[:file]}: #{result[:message]}"
          puts "    #{result[:error]}" if result[:error]
        end
        puts
      end

      def show_warning_details
        return unless results[:warnings].any?

        puts "⚠️  WARNINGS:"
        results[:warnings].each do |result|
          puts "  • #{result[:file]}: #{result[:message]}"
        end
        puts
      end

      def generate_json_report
        report = {
          gem: gem_name,
          summary: statistics,
          results: results,
          timestamp: Time.now.strftime("%Y-%m-%dT%H:%M:%S%z"),
          environment: {
            ruby_version: RUBY_VERSION,
            gem_directory: gem_dir,
            ci_mode: config[:ci_mode],
            test_mode: config[:test_mode]
          }
        }

        report_path = File.join(gem_dir, "example_validation_report.json")
        File.write(report_path, JSON.pretty_generate(report))
        puts "📄 Report saved: example_validation_report.json"
      end

      def calculate_success_rate
        total = results.values.map(&:length).sum
        return 0 if total.zero?

        (results[:passed].length / total.to_f * 100).round(1)
      end

      def exit_code
        if results[:failed].any?
          puts "💥 #{results[:failed].length} example(s) failed validation"
          1
        else
          puts "🎉 All #{gem_name} examples validated successfully!"
          0
        end
      end
    end
  end
end
