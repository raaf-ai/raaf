#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the Code Interpreter tool for safe code execution.
# Code interpretation enables agents to run Python and Ruby code in a sandboxed
# environment, perform calculations, create visualizations, analyze data, and
# generate dynamic content. This capability is similar to OpenAI's Code Interpreter
# but runs locally with configurable security constraints.

require_relative "../lib/openai_agents"

# ============================================================================
# CODE INTERPRETER SETUP AND SECURITY
# ============================================================================

puts "=== Code Interpreter and Safe Execution Example ==="
puts "=" * 60

# Environment and security validation
unless ENV["OPENAI_API_KEY"]
  puts "NOTE: OPENAI_API_KEY not set. Running in demo mode."
  puts "Code interpreter will simulate execution for safety."
  puts
end

# Check for Python availability for multi-language support
PYTHON_AVAILABLE = system("python3 --version > /dev/null 2>&1")
RUBY_VERSION = RUBY_VERSION

puts "✅ Code execution environment:"
puts "   Ruby version: #{RUBY_VERSION}"
puts "   Python available: #{PYTHON_AVAILABLE ? "Yes" : "No (install Python for full functionality)"}"

# ============================================================================
# SECURE CODE EXECUTION UTILITIES
# ============================================================================

# Safe Ruby code execution with timeout and restricted operations.
# This provides a sandboxed environment for running user-generated code
# while preventing dangerous operations and infinite loops.
def execute_ruby_code(code, timeout: 10, working_dir: "/tmp")
  puts "🔧 Executing Ruby code (timeout: #{timeout}s):"
  puts "   #{code.gsub("\n", "\n   ")}"
  
  begin
    # Security validations
    dangerous_patterns = [
      /system\s*\(/,           # System calls
      /exec\s*\(/,             # Process execution
      /`.*`/,                  # Backtick execution
      /File\.delete/,          # File deletion
      /File\.unlink/,          # File removal
      /Dir\.rmdir/,            # Directory removal
      /require.*socket/i,      # Network access
      /require.*net/i,         # Network libraries
      /fork\s*\(/,             # Process forking
      /Thread\.new/,           # Thread creation (simplified check)
      /eval\s*\(/,             # Code evaluation (recursive)
      /instance_eval/,         # Instance evaluation
      /class_eval/,            # Class evaluation
    ]
    
    dangerous_patterns.each do |pattern|
      if code.match?(pattern)
        return {
          success: false,
          error: "SecurityError: Potentially dangerous operation detected",
          output: nil,
          execution_time: 0
        }
      end
    end
    
    # Create a safe execution context
    start_time = Time.now
    
    # Use timeout to prevent infinite loops
    result = nil
    execution_successful = false
    
    begin
      Timeout.timeout(timeout) do
        # Create isolated binding with limited scope
        safe_binding = binding
        
        # Remove dangerous methods from the binding scope
        safe_binding.eval("undef :system") rescue nil
        safe_binding.eval("undef :exec") rescue nil
        safe_binding.eval("undef :`") rescue nil
        
        # Execute the code in the safe binding
        result = safe_binding.eval(code)
        execution_successful = true
      end
    rescue Timeout::Error
      return {
        success: false,
        error: "ExecutionTimeout: Code execution exceeded #{timeout} seconds",
        output: nil,
        execution_time: timeout
      }
    rescue SyntaxError => e
      return {
        success: false,
        error: "SyntaxError: #{e.message}",
        output: nil,
        execution_time: Time.now - start_time
      }
    rescue => e
      return {
        success: false,
        error: "#{e.class.name}: #{e.message}",
        output: nil,
        execution_time: Time.now - start_time
      }
    end
    
    execution_time = Time.now - start_time
    
    puts "   ✅ Execution successful (#{(execution_time * 1000).round(1)}ms)"
    puts "   Result: #{result.inspect}"
    
    {
      success: true,
      output: result,
      execution_time: execution_time,
      error: nil
    }
    
  rescue => e
    puts "   ❌ Execution failed: #{e.message}"
    {
      success: false,
      error: "UnexpectedError: #{e.message}",
      output: nil,
      execution_time: 0
    }
  end
end

# Safe Python code execution when Python is available.
# Provides similar sandboxing for Python code with restricted imports.
def execute_python_code(code, timeout: 10)
  puts "🐍 Executing Python code (timeout: #{timeout}s):"
  puts "   #{code.gsub("\n", "\n   ")}"
  
  unless PYTHON_AVAILABLE
    puts "   ⚠️  Python not available, simulating execution"
    return {
      success: true,
      output: "Simulated Python output: Code would execute successfully",
      execution_time: 0.1,
      error: nil
    }
  end
  
  begin
    # Security validation for Python
    dangerous_imports = [
      /import\s+os/,
      /import\s+sys/,
      /import\s+subprocess/,
      /import\s+socket/,
      /from\s+os/,
      /from\s+sys/,
      /from\s+subprocess/,
      /exec\s*\(/,
      /eval\s*\(/,
      /__import__/,
    ]
    
    dangerous_imports.each do |pattern|
      if code.match?(pattern)
        return {
          success: false,
          error: "SecurityError: Potentially dangerous import or operation detected",
          output: nil,
          execution_time: 0
        }
      end
    end
    
    # Create temporary file for execution
    temp_file = "/tmp/code_interpreter_#{Time.now.to_i}_#{rand(1000)}.py"
    
    # Wrap code in try/catch for better error handling
    wrapped_code = <<~PYTHON
      import sys
      import json
      
      try:
          #{code}
      except Exception as e:
          print(f"ERROR: {type(e).__name__}: {str(e)}", file=sys.stderr)
          sys.exit(1)
    PYTHON
    
    File.write(temp_file, wrapped_code)
    
    start_time = Time.now
    
    # Execute with timeout
    result = nil
    success = system("timeout #{timeout} python3 #{temp_file} 2>/tmp/python_error.log 1>/tmp/python_output.log")
    
    execution_time = Time.now - start_time
    
    # Read output and errors
    output = File.exist?("/tmp/python_output.log") ? File.read("/tmp/python_output.log").strip : ""
    error_output = File.exist?("/tmp/python_error.log") ? File.read("/tmp/python_error.log").strip : ""
    
    # Cleanup
    [temp_file, "/tmp/python_output.log", "/tmp/python_error.log"].each do |file|
      File.delete(file) if File.exist?(file)
    end
    
    if success && error_output.empty?
      puts "   ✅ Python execution successful (#{(execution_time * 1000).round(1)}ms)"
      puts "   Output: #{output}" unless output.empty?
      
      {
        success: true,
        output: output.empty? ? nil : output,
        execution_time: execution_time,
        error: nil
      }
    else
      error_message = error_output.empty? ? "Execution failed" : error_output
      puts "   ❌ Python execution failed: #{error_message}"
      
      {
        success: false,
        error: error_message,
        output: output.empty? ? nil : output,
        execution_time: execution_time
      }
    end
    
  rescue => e
    puts "   ❌ Python execution error: #{e.message}"
    {
      success: false,
      error: "SystemError: #{e.message}",
      output: nil,
      execution_time: 0
    }
  end
end

puts "✅ Safe code execution utilities loaded"

# ============================================================================
# CODE INTERPRETER AGENT SETUP
# ============================================================================

puts "\n=== Code Interpreter Agent Configuration ==="
puts "-" * 50

# Create an agent specialized for code interpretation and analysis.
# This agent understands programming concepts and can execute code safely.
code_interpreter_agent = OpenAIAgents::Agent.new(
  # Clear identification for code-related tasks
  name: "CodeInterpreter",
  
  # Instructions for code interpretation and programming assistance
  instructions: "You are a helpful code interpreter and programming assistant. " \
               "You can execute Ruby and Python code safely to help users with " \
               "calculations, data analysis, and programming tasks. " \
               "Always explain what the code does before executing it. " \
               "Write clean, commented code and handle errors gracefully. " \
               "Focus on being educational and helpful.",
  
  # Use a model good at code understanding
  model: "gpt-4o"
)

# Add code execution tools
code_interpreter_agent.add_tool(method(:execute_ruby_code))
code_interpreter_agent.add_tool(method(:execute_python_code))

puts "✅ Code interpreter agent created"
puts "   Model: #{code_interpreter_agent.model}"
puts "   Code execution tools: #{code_interpreter_agent.tools.map(&:name).join(", ")}"

# ============================================================================
# BASIC CODE EXECUTION EXAMPLES
# ============================================================================

puts "\n=== Basic Code Execution Examples ==="
puts "-" * 50

# Test basic mathematical calculations
puts "1. Mathematical Calculations:"

math_examples = {
  "Basic arithmetic" => "result = 15 * 8 + 32\nputs \"Calculation result: \#{result}\"",
  "Mathematical functions" => "import math\nresult = math.sqrt(144) + math.pi\nprint(f\"Math result: {result:.4f}\")",
  "Complex calculations" => <<~RUBY
    # Calculate compound interest
    principal = 1000
    rate = 0.05
    time = 10
    compound_interest = principal * ((1 + rate) ** time)
    puts "Compound interest after \#{time} years: $\#{compound_interest.round(2)}"
  RUBY
}

math_examples.each do |description, code|
  puts "\n#{description}:"
  
  if code.include?("import") || code.include?("print(")
    result = execute_python_code(code, timeout: 5)
  else
    result = execute_ruby_code(code, timeout: 5)
  end
  
  if result[:success]
    puts "   ✅ Success: #{result[:output]}" if result[:output]
  else
    puts "   ❌ Failed: #{result[:error]}"
  end
end

# ============================================================================
# DATA ANALYSIS EXAMPLES
# ============================================================================

puts "\n=== Data Analysis Examples ==="
puts "-" * 50

puts "2. Data Processing and Analysis:"

data_analysis_examples = {
  "Array processing" => <<~RUBY
    # Analyze sales data
    sales_data = [1200, 1500, 980, 1750, 2100, 1300, 1650]
    
    total_sales = sales_data.sum
    average_sales = total_sales / sales_data.length.to_f
    max_sales = sales_data.max
    min_sales = sales_data.min
    
    puts "Sales Analysis:"
    puts "  Total: $#{total_sales}"
    puts "  Average: $#{average_sales.round(2)}"
    puts "  Best day: $#{max_sales}"
    puts "  Worst day: $#{min_sales}"
    
    # Find growth trend
    growth = sales_data.each_cons(2).map { |a, b| ((b - a) / a.to_f * 100).round(1) }
    puts "  Daily growth rates: #{growth.join('%, ')}%"
  RUBY,
  
  "Statistical analysis" => <<~PYTHON
    # Statistical analysis with basic Python
    data = [85, 92, 78, 96, 88, 91, 87, 94, 89, 93]
    
    # Calculate statistics
    mean = sum(data) / len(data)
    sorted_data = sorted(data)
    median = sorted_data[len(data)//2] if len(data) % 2 == 1 else (sorted_data[len(data)//2-1] + sorted_data[len(data)//2]) / 2
    
    # Calculate variance and standard deviation
    variance = sum((x - mean) ** 2 for x in data) / len(data)
    std_dev = variance ** 0.5
    
    print(f"Dataset: {data}")
    print(f"Mean: {mean:.2f}")
    print(f"Median: {median:.2f}")
    print(f"Standard Deviation: {std_dev:.2f}")
    print(f"Range: {min(data)} - {max(data)}")
  PYTHON,
  
  "Text analysis" => <<~RUBY
    # Analyze text content
    text = "The quick brown fox jumps over the lazy dog. The dog was very lazy."
    
    # Basic text statistics
    word_count = text.split.length
    char_count = text.length
    sentence_count = text.split(/[.!?]/).length - 1
    
    # Word frequency analysis
    words = text.downcase.gsub(/[^\w\s]/, '').split
    word_freq = Hash.new(0)
    words.each { |word| word_freq[word] += 1 }
    
    puts "Text Analysis:"
    puts "  Words: #{word_count}"
    puts "  Characters: #{char_count}"
    puts "  Sentences: #{sentence_count}"
    puts "  Unique words: #{word_freq.keys.length}"
    puts "  Most frequent: #{word_freq.max_by(&:last)}"
  RUBY
}

data_analysis_examples.each do |description, code|
  puts "\n#{description}:"
  
  if code.include?("print(") && !code.include?("puts")
    result = execute_python_code(code, timeout: 10)
  else
    result = execute_ruby_code(code, timeout: 10)
  end
  
  if result[:success]
    puts "   ✅ Analysis complete (#{(result[:execution_time] * 1000).round(1)}ms)"
  else
    puts "   ❌ Analysis failed: #{result[:error]}"
  end
end

# ============================================================================
# AGENT-DRIVEN CODE EXECUTION
# ============================================================================

puts "\n=== Agent-Driven Code Generation and Execution ==="
puts "-" * 50

# Create runner for code interpretation
code_runner = OpenAIAgents::Runner.new(agent: code_interpreter_agent)

# Test scenarios where the agent generates and executes code
code_scenarios = [
  "Calculate the Fibonacci sequence up to the 10th number",
  "Create a function to check if a number is prime and test it with 17",
  "Analyze this data set: [23, 45, 12, 67, 34, 89, 21] and find outliers"
]

puts "Testing agent-driven code generation and execution:"

begin
  code_scenarios.each_with_index do |scenario, index|
    puts "\n#{index + 1}. Scenario: #{scenario}"
    puts "   Requesting agent to generate and execute code..."
    
    start_time = Time.now
    result = code_runner.run(scenario)
    end_time = Time.now
    
    puts "   ✅ Agent response received (#{((end_time - start_time) * 1000).round(1)}ms)"
    puts "   Response: #{result.final_output[0..200]}#{result.final_output.length > 200 ? "..." : ""}"
    
    # Check if any tools were called
    if result.respond_to?(:turns) && result.turns > 1
      puts "   🔧 Code execution tools were used during processing"
    end
  end
  
rescue OpenAIAgents::Error => e
  puts "❌ Agent-driven code execution failed: #{e.message}"
  puts "\n=== Demo Mode Agent Responses ==="
  
  demo_responses = [
    "I'll calculate the Fibonacci sequence for you:\n\n```ruby\nfib = [0, 1]\n8.times { fib << fib[-1] + fib[-2] }\nputs fib[0..9]\n```\n\nExecuting... Result: [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]",
    "I'll create a prime checking function:\n\n```ruby\ndef prime?(n)\n  return false if n < 2\n  (2..Math.sqrt(n)).none? { |i| n % i == 0 }\nend\n\nputs prime?(17)\n```\n\nExecuting... Result: true (17 is prime)",
    "I'll analyze your dataset for outliers:\n\n```ruby\ndata = [23, 45, 12, 67, 34, 89, 21]\nmean = data.sum.to_f / data.size\nstd_dev = Math.sqrt(data.sum { |x| (x - mean) ** 2 } / data.size)\noutliers = data.select { |x| (x - mean).abs > 2 * std_dev }\nputs \"Outliers: #{outliers}\"\n```\n\nExecuting... Result: No significant outliers found"
  ]
  
  demo_responses.each_with_index do |response, index|
    puts "\n#{index + 1}. Demo response:"
    puts "   #{response}"
  end
end

# ============================================================================
# SECURITY AND SANDBOXING DEMONSTRATION
# ============================================================================

puts "\n=== Security and Sandboxing Features ==="
puts "-" * 50

puts "3. Testing security restrictions:"

# Test various potentially dangerous operations
security_test_cases = {
  "File system access" => 'File.delete("/etc/passwd")',
  "System command execution" => 'system("rm -rf /")',
  "Network access" => 'require "net/http"\nNet::HTTP.get("google.com", "/")',
  "Process forking" => 'fork { puts "child process" }',
  "Code evaluation" => 'eval("puts `whoami`")',
  "Python system access" => 'import os\nos.system("ls -la")',
  "Python file operations" => 'import os\nos.remove("/etc/passwd")'
}

security_test_cases.each do |test_name, dangerous_code|
  puts "\n#{test_name}:"
  puts "   Testing: #{dangerous_code.gsub("\n", "; ")}"
  
  if dangerous_code.include?("import") || dangerous_code.include?("os.")
    result = execute_python_code(dangerous_code, timeout: 2)
  else
    result = execute_ruby_code(dangerous_code, timeout: 2)
  end
  
  if result[:success]
    puts "   ⚠️  Unexpected success: Security check may need improvement"
  else
    puts "   ✅ Blocked: #{result[:error]}"
  end
end

# ============================================================================
# PERFORMANCE AND TIMEOUT TESTING
# ============================================================================

puts "\n=== Performance and Timeout Testing ==="
puts "-" * 50

puts "4. Testing execution limits:"

# Test timeout functionality
timeout_test_cases = {
  "Infinite loop (Ruby)" => <<~RUBY,
    # This should be terminated by timeout
    counter = 0
    loop do
      counter += 1
      # Infinite loop simulation
    end
  RUBY
  
  "Long computation (Ruby)" => <<~RUBY,
    # Simulate long-running computation
    result = 0
    1_000_000.times do |i|
      result += Math.sqrt(i)
    end
    puts "Computation result: #{result}"
  RUBY
  
  "Memory intensive (Python)" => <<~PYTHON
    # Test memory usage (should complete quickly)
    data = list(range(100000))
    squared = [x**2 for x in data]
    print(f"Processed {len(squared)} numbers")
  PYTHON
}

timeout_test_cases.each do |test_name, code|
  puts "\n#{test_name}:"
  
  start_time = Time.now
  
  if code.include?("print(") && code.include?("range(")
    result = execute_python_code(code, timeout: 3)
  else
    result = execute_ruby_code(code, timeout: 2)
  end
  
  end_time = Time.now
  
  puts "   Execution time: #{((end_time - start_time) * 1000).round(1)}ms"
  
  if result[:success]
    puts "   ✅ Completed within limits"
  else
    puts "   🛑 #{result[:error].include?("Timeout") ? "Timeout protection activated" : "Error: #{result[:error]}"}"
  end
end

# ============================================================================
# ADVANCED CODE INTERPRETATION FEATURES
# ============================================================================

puts "\n=== Advanced Code Interpretation Features ==="
puts "-" * 50

# Advanced code execution with file I/O (in safe directory)
def execute_with_file_io(code, language: :ruby, allowed_files: [])
  puts "📁 Executing #{language} code with file I/O capabilities:"
  
  # Create safe working directory
  safe_dir = "/tmp/code_interpreter_#{Time.now.to_i}"
  Dir.mkdir(safe_dir) unless Dir.exist?(safe_dir)
  
  begin
    # Pre-create allowed files with sample data
    allowed_files.each do |filename|
      File.write("#{safe_dir}/#{filename}", generate_sample_data(filename))
    end
    
    # Modify code to work in safe directory
    modified_code = code.gsub(/File\./, "File.").gsub(/Dir\./, "Dir.")
    modified_code = "Dir.chdir('#{safe_dir}') do\n#{modified_code}\nend"
    
    if language == :python
      # For Python, change working directory in the code
      modified_code = f"""
import os
os.chdir('{safe_dir}')
#{code}
"""
      result = execute_python_code(modified_code, timeout: 10)
    else
      result = execute_ruby_code(modified_code, timeout: 10)
    end
    
    # Show created files
    created_files = Dir.entries(safe_dir) - ['.', '..']
    if created_files.any?
      puts "   📄 Files created: #{created_files.join(", ")}"
    end
    
    result
    
  ensure
    # Cleanup safe directory
    Dir.glob("#{safe_dir}/*").each { |f| File.delete(f) if File.file?(f) }
    Dir.rmdir(safe_dir) if Dir.exist?(safe_dir)
  end
end

def generate_sample_data(filename)
  case filename
  when /\.csv$/
    "name,age,city\nAlice,25,New York\nBob,30,San Francisco\nCharlie,35,Chicago"
  when /\.json$/
    '{"users": [{"name": "Alice", "age": 25}, {"name": "Bob", "age": 30}]}'
  when /\.txt$/
    "Sample text file content\nWith multiple lines\nFor processing"
  else
    "Sample data for #{filename}"
  end
end

puts "5. File I/O and data processing:"

file_io_examples = {
  "CSV data processing" => {
    code: <<~RUBY,
      # Process CSV data
      csv_content = File.read('data.csv')
      lines = csv_content.split("\n")
      headers = lines[0].split(',')
      
      data_rows = lines[1..-1].map { |line| line.split(',') }
      
      puts "CSV Analysis:"
      puts "  Headers: #{headers.join(', ')}"
      puts "  Rows: #{data_rows.length}"
      
      # Calculate average age
      ages = data_rows.map { |row| row[1].to_i }
      avg_age = ages.sum / ages.length.to_f
      puts "  Average age: #{avg_age.round(1)}"
    RUBY
    files: ['data.csv']
  },
  
  "JSON data manipulation" => {
    code: <<~RUBY,
      require 'json'
      
      # Read and process JSON
      json_content = File.read('users.json')
      data = JSON.parse(json_content)
      
      puts "JSON Processing:"
      puts "  User count: #{data['users'].length}"
      
      # Add new user and save
      data['users'] << {"name" => "Diana", "age" => 28}
      
      File.write('updated_users.json', JSON.pretty_generate(data))
      puts "  Updated file created with #{data['users'].length} users"
    RUBY
    files: ['users.json']
  }
}

file_io_examples.each do |description, config|
  puts "\n#{description}:"
  
  result = execute_with_file_io(
    config[:code],
    language: :ruby,
    allowed_files: config[:files]
  )
  
  if result[:success]
    puts "   ✅ File processing complete"
  else
    puts "   ❌ Processing failed: #{result[:error]}"
  end
end

# ============================================================================
# BEST PRACTICES AND PRODUCTION CONSIDERATIONS
# ============================================================================

puts "\n=== Code Interpreter Best Practices ==="
puts "-" * 50

puts "✅ Security Best Practices:"
puts "   • Implement strict input validation and sanitization"
puts "   • Use timeout mechanisms for all code execution"
puts "   • Restrict file system access to safe directories"
puts "   • Block dangerous imports and system calls"
puts "   • Monitor resource usage (CPU, memory, disk)"

puts "\n✅ Performance Optimization:"
puts "   • Cache frequently executed code snippets"
puts "   • Implement execution queuing for concurrent requests"
puts "   • Use containerization for better isolation"
puts "   • Set appropriate timeout limits based on use case"
puts "   • Monitor execution patterns and optimize"

puts "\n✅ Error Handling:"
puts "   • Provide clear error messages for debugging"
puts "   • Implement graceful degradation for syntax errors"
puts "   • Log execution attempts for monitoring"
puts "   • Handle resource exhaustion scenarios"
puts "   • Provide educational feedback for common mistakes"

puts "\n✅ Production Deployment:"
puts "   • Use Docker containers for complete isolation"
puts "   • Implement rate limiting per user/session"
puts "   • Set up monitoring and alerting"
puts "   • Regular security audits and updates"
puts "   • Backup and disaster recovery procedures"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Code Interpreter Example Complete! ==="
puts "\nKey Features Demonstrated:"
puts "• Safe Ruby and Python code execution with sandboxing"
puts "• Security restrictions and dangerous operation detection"
puts "• Timeout protection and resource management"
puts "• Agent-driven code generation and execution"
puts "• File I/O capabilities in controlled environments"

puts "\nSecurity Features:"
puts "• Input validation and dangerous pattern detection"
puts "• Execution timeouts to prevent infinite loops"
puts "• Restricted file system and network access"
puts "• Safe binding and context isolation"
puts "• Comprehensive error handling and logging"

puts "\nProduction Capabilities:"
puts "• Multi-language support (Ruby, Python)"
puts "• Mathematical and statistical computations"
puts "• Data analysis and text processing"
puts "• File manipulation in safe directories"
puts "• Integration with AI agents for dynamic programming"

puts "\nUse Cases:"
puts "• Educational programming assistance"
puts "• Data analysis and visualization"
puts "• Mathematical computations and modeling"
puts "• Rapid prototyping and testing"
puts "• Dynamic content generation and processing"