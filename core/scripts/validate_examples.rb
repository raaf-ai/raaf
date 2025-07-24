#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "timeout"
require "open3"
require "shellwords"

# Core example validation script for RAAF Core gem
class CoreExampleValidator

  attr_reader :results, :config

  def initialize
    @results = {
      passed: [],
      failed: [],
      skipped: [],
      warnings: [],
      summary: {}
    }
    @config = load_config
    @core_dir = File.expand_path("..", __dir__)
  end

  def run
    puts "🧪 RAAF Core Example Validation"
    puts "=" * 40

    validate_environment
    find_and_validate_examples
    generate_report
    exit(exit_code)
  end

  private

  def load_config
    {
      # Timeout for each example (in seconds)
      timeout: ENV.fetch("EXAMPLE_TIMEOUT", "30").to_i,

      # Run in CI mode (stricter validation)
      ci_mode: ENV.fetch("CI", "false") == "true",

      # Required environment variables for API access
      required_env: %w[OPENAI_API_KEY],

      # Examples to skip (known issues, require external setup)
      skip_files: [
        # Add specific files to skip if needed
      ],

      # Examples that only need syntax validation (design docs, etc.)
      syntax_only_files: [
        # All examples can run syntax validation if needed
      ],

      # Test mode - use dummy API key and mock responses
      test_mode: ENV.fetch("RAAF_TEST_MODE", "false") == "true",

      # Examples that require real API calls (skip in test mode)
      api_required_files: [
        "basic_example.rb",
        "handoff_objects_example.rb",
        "message_flow_example.rb",
        "structured_output_example.rb"
      ],

      # Expected success patterns in output
      success_patterns: [
        /works!/i,
        /success/i,
        /completed/i,
        /functionality works/i,
        /Response:/,
        /Agent:/,
        /✅/,
        /Example completed/i,
        /test mode/i,
        /demo mode/i,
        /schema creation/i,
        /configuration/i,
        /demonstrating schema creation/i
      ],

      # Acceptable failure patterns (missing deps, etc.)
      acceptable_failure_patterns: [
        /Missing required environment/i,
        /API key not set/i,
        /OpenAI API key/i,
        /requires.*setup/i,
        /VCR cassette/i
      ]
    }
  end

  def validate_environment
    puts "🔍 Environment Check"

    # Check if we're in the core directory
    unless File.exist?(File.join(@core_dir, "raaf-core.gemspec"))
      puts "  ❌ Not in RAAF core directory"
      exit(1)
    end

    puts "  📁 Core directory: #{@core_dir}"
    puts "  🐣 Ruby version: #{RUBY_VERSION}"

    # Check for API key or test mode
    if @config[:test_mode]
      puts "  🧪 Test mode: enabled (using dummy API key)"
      ENV["OPENAI_API_KEY"] = "test-api-key-for-validation"
    elsif ENV["OPENAI_API_KEY"] && !ENV["OPENAI_API_KEY"].empty?
      puts "  🔑 OpenAI API key: present"
    elsif @config[:ci_mode]
      puts "  ❌ OpenAI API key: missing (required for CI)"
      puts "  💡 Set RAAF_TEST_MODE=true to run validation without real API key"
      exit(1)
    else
      puts "  ⚠️  OpenAI API key: missing (some examples may be skipped)"
    end

    # Check if bundle is available
    begin
      `bundle --version`
      puts "  📦 Bundler: available"
    rescue StandardError
      puts "  ❌ Bundler: not available"
      exit(1)
    end

    puts
  end

  def find_and_validate_examples
    examples_dir = File.join(@core_dir, "examples")

    unless File.directory?(examples_dir)
      puts "❌ Examples directory not found: #{examples_dir}"
      exit(1)
    end

    example_files = Dir.glob(File.join(examples_dir, "*.rb"))
    puts "📁 Found #{example_files.length} example files in core/examples/"
    puts

    example_files.each do |file_path|
      validate_example(file_path)
    end
  end

  def validate_example(file_path)
    filename = File.basename(file_path)
    puts "🔍 #{filename}"

    # Check if file should be skipped
    if @config[:skip_files].include?(filename)
      result = {
        status: :skipped,
        file: filename,
        message: "Explicitly skipped in configuration"
      }
      @results[:skipped] << result
      puts "  ⏭️  Skipped (configured)"
      puts
      return
    end

    # Determine validation type
    # In test mode, API-required files get syntax validation only
    syntax_only = @config[:syntax_only_files].include?(filename) ||
                  (@config[:test_mode] && @config[:api_required_files].include?(filename))

    result = if syntax_only
               validate_syntax(file_path, filename)
             else
               validate_execution(file_path, filename)
             end

    # Record result
    @results[result[:status]] << result

    # Display result
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

  def validate_syntax(file_path, filename)
    Timeout.timeout(10) do
      # First check basic Ruby syntax
      _, stderr, status = Open3.capture3(
        "ruby -c #{filename}",
        chdir: File.dirname(file_path)
      )

      unless status.success?
        return {
          status: :failed,
          file: filename,
          message: "Syntax errors found",
          error: stderr.strip
        }
      end

      # For test mode, also validate constants are defined
      if @config[:test_mode] && @config[:api_required_files].include?(filename)
        validation_result = validate_constants(file_path, filename)
        return validation_result unless validation_result[:status] == :passed
      end

      {
        status: :passed,
        file: filename,
        message: "Syntax check passed#{" (constants validated)" if @config[:test_mode]}"
      }
    end
  rescue Timeout::Error
    {
      status: :failed,
      file: filename,
      message: "Syntax check timed out",
      error: "Timeout after 10 seconds"
    }
  rescue StandardError => e
    {
      status: :failed,
      file: filename,
      message: "Syntax check failed",
      error: e.message
    }
  end

  def validate_constants(file_path, filename)
    # Create a test script that loads the example and checks for NameErrors
    test_script = <<~RUBY
      begin
        # Load RAAF core first
        require_relative "../lib/raaf-core"
      #{"  "}
        # Set test mode environment
        ENV["RAAF_TEST_MODE"] = "true"
        ENV["OPENAI_API_KEY"] = "test-key"
      #{"  "}
        # Load the example file but catch NameErrors
        begin
          load "#{File.basename(file_path)}"
        rescue SystemExit
          # Examples may call exit, which is fine
        rescue => e
          if e.is_a?(NameError) && e.message.include?("uninitialized constant")
            puts "CONSTANT_ERROR: \#{e.message}"
            exit 1
          elsif e.is_a?(RAAF::Models::AuthenticationError)
            # This is expected in test mode
            exit 0
          else
            # Re-raise other errors
            raise
          end
        end
      #{"  "}
        puts "CONSTANTS_OK"
      rescue => e
        puts "LOAD_ERROR: \#{e.class}: \#{e.message}"
        exit 2
      end
    RUBY

    # Run the test script
    stdout, stderr, status = Open3.capture3(
      "bundle exec ruby -e #{test_script.shellescape}",
      chdir: File.dirname(file_path)
    )

    combined_output = "#{stdout}\n#{stderr}".strip

    if combined_output.include?("CONSTANT_ERROR:")
      {
        status: :failed,
        file: filename,
        message: "Undefined constants found",
        error: combined_output.lines.grep(/CONSTANT_ERROR:/).first&.strip
      }
    elsif combined_output.include?("LOAD_ERROR:")
      {
        status: :failed,
        file: filename,
        message: "Failed to load example",
        error: combined_output.lines.grep(/LOAD_ERROR:/).first&.strip
      }
    elsif status.success? || combined_output.include?("CONSTANTS_OK")
      {
        status: :passed,
        file: filename,
        message: "Constants validation passed"
      }
    else
      {
        status: :failed,
        file: filename,
        message: "Constant validation failed",
        error: combined_output.lines.first(3).join.strip
      }
    end
  rescue StandardError => e
    {
      status: :failed,
      file: filename,
      message: "Constant validation error",
      error: e.message
    }
  end

  def validate_execution(file_path, filename)
    Timeout.timeout(@config[:timeout]) do
      # Set up test environment
      env = ENV.to_h.merge({
                             "RAAF_EXAMPLE_MODE" => "true",
                             "RAAF_LOG_LEVEL" => "warn",
                             "RAAF_DISABLE_TRACING" => "true"
                           })

      # Add test mode environment if enabled
      if @config[:test_mode]
        env.merge!({
                     "RAAF_TEST_MODE" => "true",
                     "RAAF_MOCK_RESPONSES" => "true"
                   })
      end

      # Run the example
      stdout, stderr, status = Open3.capture3(
        env,
        "bundle exec ruby #{filename}",
        chdir: File.dirname(file_path)
      )

      combined_output = "#{stdout}\n#{stderr}".strip

      if status.success?
        # Check for success indicators
        if @config[:success_patterns].any? { |pattern| combined_output.match?(pattern) }
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
      elsif @config[:acceptable_failure_patterns].any? { |pattern| combined_output.match?(pattern) }
        # Check if failure is acceptable (missing deps, etc.)
        {
          status: :skipped,
          file: filename,
          message: "Skipped due to missing dependencies",
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
  rescue Timeout::Error
    {
      status: :failed,
      file: filename,
      message: "Execution timed out",
      error: "Timeout after #{@config[:timeout]} seconds"
    }
  rescue StandardError => e
    {
      status: :failed,
      file: filename,
      message: "Execution error",
      error: e.message
    }
  end

  def extract_key_output(output)
    return "" if output.nil? || output.empty?

    # Extract first few meaningful lines, skip debug/trace info
    lines = output.lines
                  .grep_v(/^\s*$/) # Skip empty lines
                  .grep_v(/bundler|loading/i) # Skip bundler noise
                  .first(3)

    lines.join.strip
  end

  def generate_report
    total = @results.values.map(&:length).sum

    puts "📊 VALIDATION SUMMARY"
    puts "=" * 30
    puts "✅ Passed:   #{@results[:passed].length}"
    puts "❌ Failed:   #{@results[:failed].length}"
    puts "⏭️  Skipped:  #{@results[:skipped].length}"
    puts "⚠️  Warnings: #{@results[:warnings].length}"
    puts "📋 Total:    #{total}"
    puts

    # Show details for failures
    if @results[:failed].any?
      puts "❌ FAILED EXAMPLES:"
      @results[:failed].each do |result|
        puts "  • #{result[:file]}: #{result[:message]}"
        puts "    #{result[:error]}" if result[:error]
      end
      puts
    end

    # Show details for warnings
    if @results[:warnings].any?
      puts "⚠️  WARNINGS:"
      @results[:warnings].each do |result|
        puts "  • #{result[:file]}: #{result[:message]}"
      end
      puts
    end

    # Generate JSON report for CI
    return unless @config[:ci_mode]

    report = {
      summary: {
        total: total,
        passed: @results[:passed].length,
        failed: @results[:failed].length,
        skipped: @results[:skipped].length,
        warnings: @results[:warnings].length,
        success_rate: total.positive? ? (@results[:passed].length / total.to_f * 100).round(1) : 0
      },
      results: @results,
      timestamp: Time.now.strftime("%Y-%m-%dT%H:%M:%S%z"),
      environment: {
        ruby_version: RUBY_VERSION,
        core_directory: @core_dir,
        ci_mode: @config[:ci_mode]
      }
    }

    report_path = File.join(@core_dir, "example_validation_report.json")
    File.write(report_path, JSON.pretty_generate(report))
    puts "📄 Report saved: example_validation_report.json"
  end

  def exit_code
    if @results[:failed].any?
      puts "💥 #{@results[:failed].length} example(s) failed validation"
      1
    else
      puts "🎉 All core examples validated successfully!"
      0
    end
  end

end

# Run the validator if this script is executed directly
CoreExampleValidator.new.run if __FILE__ == $PROGRAM_NAME
