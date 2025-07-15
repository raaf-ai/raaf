#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the LocalShellTool integration with OpenAI Agents Ruby.
# LocalShellTool provides secure, controlled access to shell commands for AI agents.
# Unlike ComputerTool which provides full desktop control, this focuses on command-line
# operations with built-in security features including command whitelisting,
# directory restrictions, timeout protection, and output size limits.

require_relative "../lib/openai_agents"

# No API key required for local shell operations
# The tool works entirely locally without external API calls

puts "=== Local Shell Tool Example ==="
puts

# ============================================================================
# TOOL SETUP
# ============================================================================

# Create a basic local shell tool with default security settings
shell_tool = OpenAIAgents::Tools::LocalShellTool.new(
  working_dir: Dir.pwd,        # Start in current directory
  timeout: 30,                 # 30 second timeout for commands
  max_output: 10_000          # Limit output to 10KB
)

puts "Local shell tool initialized:"
puts "- Working directory: #{shell_tool.working_dir}"
puts "- Allowed commands: #{shell_tool.allowed_commands.join(", ")}"
puts

# ============================================================================
# EXAMPLE 1: BASIC SHELL OPERATIONS
# ============================================================================

puts "1. Basic shell operations:"

# Create an agent with shell access
shell_agent = OpenAIAgents::Agent.new(
  name: "ShellAgent",
  instructions: "You are a system assistant with access to shell commands. Help users with file operations, system information, and development tasks. Always use safe commands.",
  model: "gpt-4o"
)

# Add shell tool to the agent
shell_agent.add_tool(shell_tool)

# Create runner
runner = OpenAIAgents::Runner.new(agent: shell_agent)

# Test basic shell operations
begin
  basic_messages = [{
    role: "user",
    content: "Please list the files in the current directory and show me the current date."
  }]

  result = runner.run(basic_messages)
  puts "Basic shell result: #{result.final_output}"
rescue StandardError => e
  puts "Basic shell error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 2: DEVELOPMENT ASSISTANT
# ============================================================================

puts "2. Development assistant:"

# Create a development-focused agent
dev_agent = OpenAIAgents::Agent.new(
  name: "DevAssistant",
  instructions: "You are a development assistant with shell access. Help with git operations, file management, and development workflow tasks. Always explain what commands you're running.",
  model: "gpt-4o"
)

# Add shell tool
dev_agent.add_tool(shell_tool)

# Create runner
dev_runner = OpenAIAgents::Runner.new(agent: dev_agent)

# Test development operations
begin
  dev_messages = [{
    role: "user",
    content: "Check the git status of this project and show me the most recent commit."
  }]

  dev_result = dev_runner.run(dev_messages)
  puts "Development result: #{dev_result.final_output}"
rescue StandardError => e
  puts "Development error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 3: SECURE SHELL WITH CUSTOM WHITELIST
# ============================================================================

puts "3. Secure shell with custom whitelist:"

# Create a restricted shell tool with limited commands
restricted_shell = OpenAIAgents::Tools::LocalShellTool.new(
  allowed_commands: ["ls", "cat", "grep", "find", "wc", "sort", "head", "tail"],
  working_dir: Dir.pwd,
  timeout: 15,
  max_output: 5_000
)

# Create a restricted agent
restricted_agent = OpenAIAgents::Agent.new(
  name: "RestrictedAgent",
  instructions: "You are a restricted shell assistant. You can only use basic file reading and searching commands. Help users examine files safely.",
  model: "gpt-4o"
)

# Add restricted shell tool
restricted_agent.add_tool(restricted_shell)

# Create runner
restricted_runner = OpenAIAgents::Runner.new(agent: restricted_agent)

# Test restricted operations
begin
  restricted_messages = [{
    role: "user",
    content: "Find all Ruby files in this directory and show me the first 10 lines of each."
  }]

  restricted_result = restricted_runner.run(restricted_messages)
  puts "Restricted shell result: #{restricted_result.final_output}"
rescue StandardError => e
  puts "Restricted shell error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 4: ADVANCED SHELL TOOL
# ============================================================================

puts "4. Advanced shell tool:"

# Create an advanced shell tool with extended capabilities
advanced_shell = OpenAIAgents::Tools::AdvancedShellTool.new(
  working_dir: Dir.pwd,
  timeout: 60,
  max_output: 20_000
)

# Create an advanced agent
advanced_agent = OpenAIAgents::Agent.new(
  name: "AdvancedAgent",
  instructions: "You are an advanced system assistant with extended shell capabilities. Help with complex operations, pipelines, and system analysis.",
  model: "gpt-4o"
)

# Add advanced shell tool
advanced_agent.add_tool(advanced_shell)

# Create runner
advanced_runner = OpenAIAgents::Runner.new(agent: advanced_agent)

# Test advanced operations
begin
  advanced_messages = [{
    role: "user",
    content: "Create a pipeline to find all Ruby files, count the lines in each, and show me the top 5 largest files."
  }]

  advanced_result = advanced_runner.run(advanced_messages)
  puts "Advanced shell result: #{advanced_result.final_output}"
rescue StandardError => e
  puts "Advanced shell error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 5: FILE SYSTEM ANALYSIS
# ============================================================================

puts "5. File system analysis:"

# Define additional analysis tools
def analyze_file_structure(path:)
  # Simulate file structure analysis
  "File structure analysis for: #{path} - Directory tree and file organization examined."
end

def security_scan(directory:)
  # Simulate security scanning
  "Security scan results for: #{directory} - No suspicious files or permissions detected."
end

# Create a file system analysis agent
fs_agent = OpenAIAgents::Agent.new(
  name: "FileSystemAgent",
  instructions: "You are a file system analysis assistant. Use shell commands to examine directory structures and provide insights about file organization and security.",
  model: "gpt-4o"
)

# Add shell tool and analysis tools
fs_agent.add_tool(shell_tool)
fs_agent.add_tool(method(:analyze_file_structure))
fs_agent.add_tool(method(:security_scan))

# Create runner
fs_runner = OpenAIAgents::Runner.new(agent: fs_agent)

# Test file system analysis
begin
  fs_messages = [{
    role: "user",
    content: "Analyze the file structure of this project and perform a basic security scan."
  }]

  fs_result = fs_runner.run(fs_messages)
  puts "File system analysis result: #{fs_result.final_output}"
rescue StandardError => e
  puts "File system analysis error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 6: COMMAND VALIDATION AND SECURITY
# ============================================================================

puts "6. Command validation and security:"

# Test various commands to show security features
test_commands = [
  "ls -la",               # Safe command
  "cat /etc/passwd",      # Safe but sensitive
  "rm -rf /",             # Blocked command
  "sudo whoami",          # Blocked command
  "find . -name '*.rb'",  # Safe command
  "curl google.com"       # Safe but network command
]

puts "Testing command validation:"
test_commands.each do |cmd|
  begin
    # Try to execute each command directly
    result = shell_tool.call(command: cmd)
    puts "✅ '#{cmd}' - Success: #{result[:success]}"
    puts "   Output: #{result[:stdout][0..100]}..." if result[:stdout]
    puts "   Error: #{result[:stderr]}" if result[:stderr] && !result[:stderr].empty?
  rescue SecurityError => e
    puts "🚫 '#{cmd}' - Security blocked: #{e.message}"
  rescue StandardError => e
    puts "❌ '#{cmd}' - Error: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 7: WORKING DIRECTORY MANAGEMENT
# ============================================================================

puts "7. Working directory management:"

# Create a temporary directory for testing
temp_dir = "/tmp/openai_agents_test"
begin
  # Create test directory
  Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)
  
  # Create shell tool with specific working directory
  wd_shell = OpenAIAgents::Tools::LocalShellTool.new(
    working_dir: temp_dir,
    timeout: 30
  )
  
  # Test working directory operations
  puts "Testing working directory operations in: #{temp_dir}"
  
  # Create some test files
  result1 = wd_shell.call(command: "touch test1.txt test2.txt")
  puts "Create files: #{result1[:success] ? 'Success' : 'Failed'}"
  
  # List files
  result2 = wd_shell.call(command: "ls -la")
  puts "List files: #{result2[:stdout]}"
  
  # Try to access outside working directory (should fail)
  result3 = wd_shell.call(command: "ls", working_dir: "/etc")
  puts "Access outside directory: #{result3[:error] || 'Unexpectedly succeeded'}"
  
rescue StandardError => e
  puts "Working directory test error: #{e.message}"
ensure
  # Clean up
  system("rm -rf #{temp_dir}") if Dir.exist?(temp_dir)
end

puts

# ============================================================================
# EXAMPLE 8: TIMEOUT AND OUTPUT LIMITS
# ============================================================================

puts "8. Timeout and output limits:"

# Create a shell tool with strict limits
limited_shell = OpenAIAgents::Tools::LocalShellTool.new(
  timeout: 5,      # 5 second timeout
  max_output: 500  # 500 character limit
)

# Test timeout with a long-running command
puts "Testing timeout with sleep command:"
begin
  result = limited_shell.call(command: "sleep 10")
  puts "Sleep result: #{result[:timeout] ? 'Timed out as expected' : 'Unexpectedly completed'}"
rescue StandardError => e
  puts "Sleep error: #{e.message}"
end

# Test output limit with a command that produces lots of output
puts "Testing output limit with large output:"
begin
  result = limited_shell.call(command: "find / -name '*.txt' 2>/dev/null")
  puts "Find result length: #{result[:stdout].length} characters"
  puts "Truncated: #{result[:stdout].include?('... (truncated)') ? 'Yes' : 'No'}"
rescue StandardError => e
  puts "Find error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 9: ENVIRONMENT VARIABLES
# ============================================================================

puts "9. Environment variables:"

# Create shell tool with custom environment variables
env_shell = OpenAIAgents::Tools::LocalShellTool.new(
  env_vars: {
    "CUSTOM_VAR" => "Hello from OpenAI Agents",
    "PATH" => ENV["PATH"]  # Preserve existing PATH
  }
)

# Test environment variable access
puts "Testing environment variables:"
begin
  result = env_shell.call(command: "echo $CUSTOM_VAR")
  puts "Custom variable: #{result[:stdout].strip}"
  
  result2 = env_shell.call(command: "env | grep CUSTOM")
  puts "Environment check: #{result2[:stdout].strip}"
rescue StandardError => e
  puts "Environment test error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 10: PIPELINE OPERATIONS
# ============================================================================

puts "10. Pipeline operations (Advanced Shell Tool):"

# Test pipeline functionality with advanced shell tool
if defined?(OpenAIAgents::Tools::AdvancedShellTool)
  begin
    pipeline_result = advanced_shell.execute_pipeline(
      commands: [
        ["find", ".", "-name", "*.rb"],
        ["head", "-20"],
        ["wc", "-l"]
      ]
    )
    
    puts "Pipeline result: #{pipeline_result[:stdout]}"
  rescue StandardError => e
    puts "Pipeline error: #{e.message}"
  end
else
  puts "Advanced shell tool not available for pipeline testing"
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Local Shell Tool Configuration ==="
puts "Default timeout: #{OpenAIAgents::Tools::LocalShellTool::DEFAULT_TIMEOUT} seconds"
puts "Default max output: #{OpenAIAgents::Tools::LocalShellTool::DEFAULT_MAX_OUTPUT} characters"
puts "Default allowed commands: #{OpenAIAgents::Tools::LocalShellTool::DEFAULT_ALLOWED_COMMANDS.size} commands"
puts "Blocked commands: #{OpenAIAgents::Tools::LocalShellTool::BLOCKED_COMMANDS.join(", ")}"
puts "Working directory: #{shell_tool.working_dir}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Local Shell Tool Features:"
puts "1. Secure command execution with whitelist validation"
puts "2. Working directory restrictions and isolation"
puts "3. Timeout protection against long-running commands"
puts "4. Output size limits to prevent memory issues"
puts "5. Environment variable control"
puts "6. Command argument parsing and validation"
puts "7. Directory traversal protection"
puts "8. Extensible command set with AdvancedShellTool"
puts
puts "Security Features:"
puts "- Command whitelist prevents dangerous operations"
puts "- Blocked commands list stops destructive actions"
puts "- Directory restrictions prevent unauthorized access"
puts "- Timeout protection against infinite loops"
puts "- Output limits prevent resource exhaustion"
puts "- Environment isolation controls variable access"
puts
puts "Best Practices:"
puts "- Use restrictive command whitelists for production"
puts "- Set appropriate timeouts for your use case"
puts "- Limit output size to prevent memory issues"
puts "- Use dedicated working directories for isolation"
puts "- Monitor and log shell command usage"
puts "- Regularly review and update allowed commands"
puts "- Test security features with various command attempts"
puts "- Implement proper error handling and user feedback"
puts
puts "Use Cases:"
puts "- Development workflow automation"
puts "- File system analysis and management"
puts "- System monitoring and diagnostics"
puts "- Data processing pipelines"
puts "- Code repository operations"
puts "- Log analysis and searching"
puts "- Build and deployment scripts"
puts "- System administration tasks"