# frozen_string_literal: true

# Code Validator for RAAF Guides
# Extracts and validates Ruby code examples from guide markdown files

require 'pathname'
require 'tempfile'
require 'bundler'

class CodeValidator
  class CodeBlock
    attr_reader :content, :file, :line_number, :context

    def initialize(content, file, line_number, context = nil)
      @content = content
      @file = file
      @line_number = line_number
      @context = context
    end

    def location
      "#{file}:#{line_number}"
    end
  end

  class ValidationResult
    attr_reader :code_block, :success, :error, :output

    def initialize(code_block, success, error = nil, output = nil)
      @code_block = code_block
      @success = success
      @error = error
      @output = output
    end

    def failed?
      !success
    end
  end

  def initialize(guides_dir = "source", raaf_root = "..")
    @guides_dir = Pathname.new(guides_dir)
    @raaf_root = Pathname.new(raaf_root)
    @results = []
  end

  def extract_code_blocks(file_pattern = "*.md")
    code_blocks = []
    
    Dir.glob(@guides_dir.join(file_pattern)).each do |file_path|
      file_content = File.read(file_path)
      relative_path = Pathname.new(file_path).relative_path_from(@guides_dir)
      
      # Extract Ruby code blocks
      code_blocks.concat(extract_ruby_blocks(file_content, relative_path))
    end
    
    code_blocks
  end

  def validate_code_blocks(code_blocks)
    @results = []
    
    code_blocks.each do |code_block|
      result = validate_single_block(code_block)
      @results << result
      
      if result.failed?
        puts "❌ FAILED: #{code_block.location}"
        puts "   Error: #{result.error}"
        puts "   Code: #{code_block.content[0..100]}..."
      else
        puts "✅ PASSED: #{code_block.location}"
      end
    end
    
    @results
  end

  def summary
    total = @results.length
    passed = @results.count(&:success)
    failed = total - passed
    
    puts "\n" + "="*50
    puts "Code Validation Summary"
    puts "="*50
    puts "Total code blocks: #{total}"
    puts "Passed: #{passed}"
    puts "Failed: #{failed}"
    puts "Success rate: #{total > 0 ? (passed.to_f / total * 100).round(1) : 0}%"
    
    if failed > 0
      puts "\nFailed blocks:"
      @results.select(&:failed?).each do |result|
        puts "  - #{result.code_block.location}: #{result.error}"
      end
    end
    
    failed == 0
  end

  private

  def extract_ruby_blocks(content, file_path)
    blocks = []
    lines = content.lines
    in_ruby_block = false
    current_block = []
    block_start_line = 0
    
    lines.each_with_index do |line, index|
      line_number = index + 1
      
      if line.strip.start_with?('```ruby')
        in_ruby_block = true
        current_block = []
        block_start_line = line_number + 1
      elsif line.strip == '```' && in_ruby_block
        if current_block.any?
          code_content = current_block.join
          blocks << CodeBlock.new(code_content, file_path, block_start_line)
        end
        in_ruby_block = false
      elsif in_ruby_block
        current_block << line
      end
    end
    
    blocks
  end

  def validate_single_block(code_block)
    # Create a temporary file with the code
    temp_file = Tempfile.new(['code_block', '.rb'])
    
    begin
      # Add RAAF requires and setup
      full_code = build_test_code(code_block.content)
      temp_file.write(full_code)
      temp_file.flush
      
      # Run syntax check first
      syntax_result = run_syntax_check(temp_file.path)
      return ValidationResult.new(code_block, false, syntax_result) unless syntax_result.nil?
      
      # Run the code
      execution_result = run_code_execution(temp_file.path)
      
      if execution_result[:success]
        ValidationResult.new(code_block, true, nil, execution_result[:output])
      else
        ValidationResult.new(code_block, false, execution_result[:error])
      end
      
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  def build_test_code(code_content)
    # Build a complete, testable Ruby script
    <<~RUBY
      # Test setup for RAAF guide code
      begin
        require 'bundler/setup'
        
        # Add RAAF core to load path
        $LOAD_PATH.unshift File.expand_path('#{@raaf_root}/core/lib')
        
        # Try to require RAAF
        begin
          require 'raaf'
        rescue LoadError => e
          # If RAAF not available, create mock classes for syntax checking
          module RAAF
            class Agent
              def initialize(*args, **kwargs); end
              def add_tool(tool); end
              def run(message); end
            end
            
            class Runner
              def initialize(*args, **kwargs); end
              def run(message); end
            end
            
            module DSL
              class AgentBuilder
                def self.build(&block); new.tap(&block); end
                def method_missing(name, *args, &block); end
              end
            end
          end
        end
        
        # Guide code starts here
        #{code_content}
        
        # If we get here, the code executed successfully
        puts "Code executed successfully"
        
      rescue => e
        puts "Error: \#{e.class}: \#{e.message}"
        puts e.backtrace.first(3).join("\\n") if e.backtrace
        exit 1
      end
    RUBY
  end

  def run_syntax_check(file_path)
    result = `ruby -c "#{file_path}" 2>&1`
    return result.strip unless $?.success?
    nil
  end

  def run_code_execution(file_path)
    # Run with timeout to prevent hanging
    output = ""
    error = nil
    
    begin
      # Change to raaf root directory for execution
      Dir.chdir(@raaf_root) do
        # Run with bundler context and timeout
        result = Bundler.with_original_env do
          `timeout 10s ruby "#{file_path}" 2>&1`
        end
        
        if $?.success?
          { success: true, output: result.strip }
        else
          { success: false, error: result.strip }
        end
      end
    rescue => e
      { success: false, error: "Execution error: #{e.message}" }
    end
  end
end

# CLI interface
if __FILE__ == $0
  # Support for GUIDE_PATTERN environment variable
  pattern = ENV['GUIDE_PATTERN'] || "*.md"
  
  validator = CodeValidator.new
  
  puts "Extracting code blocks from guides (pattern: #{pattern})..."
  code_blocks = validator.extract_code_blocks(pattern)
  
  puts "Found #{code_blocks.length} Ruby code blocks"
  puts "Validating code blocks...\n"
  
  validator.validate_code_blocks(code_blocks)
  success = validator.summary
  
  exit(success ? 0 : 1)
end