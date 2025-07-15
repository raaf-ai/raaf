#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the FileSearchTool integration with OpenAI Agents Ruby.
# FileSearchTool provides powerful file and content searching capabilities for AI agents.
# It includes both local file search and hosted file search (through OpenAI API).
# The tool can search file contents, filenames, or both, with support for caching,
# file filtering, and context-aware results.

require_relative "../lib/openai_agents"

# No API key required for local file search operations
# The tool works entirely locally for content and filename searches

puts "=== File Search Tool Example ==="
puts

# ============================================================================
# TOOL SETUP
# ============================================================================

# Create a local file search tool with basic configuration
file_search_tool = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["."],           # Search in current directory
  file_extensions: [".rb", ".md", ".txt", ".yml", ".yaml", ".json"],
  max_results: 10                # Limit results for readability
)

puts "File search tool initialized:"
puts "- Search paths: #{file_search_tool.instance_variable_get(:@search_paths)}"
puts "- Max results: #{file_search_tool.instance_variable_get(:@max_results)}"
puts

# ============================================================================
# EXAMPLE 1: BASIC FILE CONTENT SEARCH
# ============================================================================

puts "1. Basic file content search:"

# Create an agent with file search capability
search_agent = OpenAIAgents::Agent.new(
  name: "FileSearchAgent",
  instructions: "You are a code search assistant. Use file search to find relevant code, documentation, and configuration files. Always provide context for your findings.",
  model: "gpt-4o"
)

# Add file search tool to the agent
search_agent.add_tool(file_search_tool)

# Create runner
runner = OpenAIAgents::Runner.new(agent: search_agent)

# Test basic content search
begin
  content_search_messages = [{
    role: "user",
    content: "Search for files that contain 'OpenAI' in their content."
  }]

  content_result = runner.run(content_search_messages)
  puts "Content search result: #{content_result.final_output}"
rescue StandardError => e
  puts "Content search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 2: FILENAME SEARCH
# ============================================================================

puts "2. Filename search:"

# Create an agent specialized for filename searches
filename_agent = OpenAIAgents::Agent.new(
  name: "FilenameAgent",
  instructions: "You are a file organization assistant. Use filename search to help users find files by their names and organize their codebase.",
  model: "gpt-4o"
)

# Add file search tool
filename_agent.add_tool(file_search_tool)

# Create runner
filename_runner = OpenAIAgents::Runner.new(agent: filename_agent)

# Test filename search
begin
  filename_messages = [{
    role: "user",
    content: "Find all files with 'example' in their filename."
  }]

  filename_result = filename_runner.run(filename_messages)
  puts "Filename search result: #{filename_result.final_output}"
rescue StandardError => e
  puts "Filename search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 3: COMBINED SEARCH (BOTH CONTENT AND FILENAME)
# ============================================================================

puts "3. Combined search (both content and filename):"

# Create an agent that searches both content and filenames
combined_agent = OpenAIAgents::Agent.new(
  name: "CombinedSearchAgent",
  instructions: "You are a comprehensive search assistant. Use both content and filename search to provide thorough search results.",
  model: "gpt-4o"
)

# Add file search tool
combined_agent.add_tool(file_search_tool)

# Create runner
combined_runner = OpenAIAgents::Runner.new(agent: combined_agent)

# Test combined search
begin
  combined_messages = [{
    role: "user",
    content: "Search for anything related to 'agent' - both in file content and filenames."
  }]

  combined_result = combined_runner.run(combined_messages)
  puts "Combined search result: #{combined_result.final_output}"
rescue StandardError => e
  puts "Combined search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 4: DEVELOPMENT WORKFLOW ASSISTANT
# ============================================================================

puts "4. Development workflow assistant:"

# Define additional development tools
def analyze_code_pattern(pattern:, files:)
  # Simulate code pattern analysis
  "Code pattern analysis for '#{pattern}' across #{files.size} files: Common patterns and usage identified."
end

def generate_documentation(files:, doc_type: "overview")
  # Simulate documentation generation
  "Generated #{doc_type} documentation for #{files.size} files: Structure and API documented."
end

# Create a development-focused agent
dev_agent = OpenAIAgents::Agent.new(
  name: "DevWorkflowAgent",
  instructions: "You are a development workflow assistant. Use file search to analyze codebases, find patterns, and help with development tasks.",
  model: "gpt-4o"
)

# Add search and analysis tools
dev_agent.add_tool(file_search_tool)
dev_agent.add_tool(method(:analyze_code_pattern))
dev_agent.add_tool(method(:generate_documentation))

# Create runner
dev_runner = OpenAIAgents::Runner.new(agent: dev_agent)

# Test development workflow
begin
  dev_messages = [{
    role: "user",
    content: "Find all Ruby files that define classes, analyze the class patterns, and help me generate documentation."
  }]

  dev_result = dev_runner.run(dev_messages)
  puts "Development workflow result: #{dev_result.final_output}"
rescue StandardError => e
  puts "Development workflow error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 5: CONFIGURATION FILE SEARCH
# ============================================================================

puts "5. Configuration file search:"

# Create a specialized configuration search tool
config_search_tool = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["."],
  file_extensions: [".yml", ".yaml", ".json", ".toml", ".ini", ".conf", ".cfg"],
  max_results: 15
)

# Create a configuration management agent
config_agent = OpenAIAgents::Agent.new(
  name: "ConfigAgent",
  instructions: "You are a configuration management assistant. Help users find and analyze configuration files in their projects.",
  model: "gpt-4o"
)

# Add configuration search tool
config_agent.add_tool(config_search_tool)

# Create runner
config_runner = OpenAIAgents::Runner.new(agent: config_agent)

# Test configuration search
begin
  config_messages = [{
    role: "user",
    content: "Find all configuration files and search for any database-related settings."
  }]

  config_result = config_runner.run(config_messages)
  puts "Configuration search result: #{config_result.final_output}"
rescue StandardError => e
  puts "Configuration search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 6: SECURITY AUDIT ASSISTANT
# ============================================================================

puts "6. Security audit assistant:"

# Define security analysis tools
def security_analysis(files:, analysis_type: "vulnerability")
  # Simulate security analysis
  case analysis_type.downcase
  when "vulnerability"
    "Vulnerability analysis of #{files.size} files: No critical security issues found."
  when "secrets"
    "Secrets scan of #{files.size} files: No exposed API keys or passwords detected."
  when "permissions"
    "Permissions analysis of #{files.size} files: File permissions reviewed."
  else
    "Security analysis type '#{analysis_type}' not supported."
  end
end

def compliance_check(files:, standard: "general")
  # Simulate compliance checking
  "Compliance check (#{standard}) for #{files.size} files: Files reviewed for compliance standards."
end

# Create a security-focused agent
security_agent = OpenAIAgents::Agent.new(
  name: "SecurityAuditAgent",
  instructions: "You are a security audit assistant. Use file search to find potential security issues, exposed secrets, and compliance violations.",
  model: "gpt-4o"
)

# Add security tools
security_agent.add_tool(file_search_tool)
security_agent.add_tool(method(:security_analysis))
security_agent.add_tool(method(:compliance_check))

# Create runner
security_runner = OpenAIAgents::Runner.new(agent: security_agent)

# Test security audit
begin
  security_messages = [{
    role: "user",
    content: "Search for any files that might contain API keys, passwords, or other sensitive information."
  }]

  security_result = security_runner.run(security_messages)
  puts "Security audit result: #{security_result.final_output}"
rescue StandardError => e
  puts "Security audit error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 7: DIRECT TOOL USAGE
# ============================================================================

puts "7. Direct tool usage:"

# Test direct tool usage with different search types
search_tests = [
  { query: "def initialize", search_type: "content", description: "Find constructor methods" },
  { query: "spec", search_type: "filename", description: "Find test files" },
  { query: "require", search_type: "both", description: "Find require statements and files" }
]

search_tests.each do |test|
  puts "\n#{test[:description]}:"
  begin
    result = file_search_tool.call(
      query: test[:query],
      search_type: test[:search_type]
    )
    puts result[0..300] + (result.length > 300 ? "..." : "")
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 8: PATTERN-BASED SEARCH
# ============================================================================

puts "8. Pattern-based search:"

# Create a pattern search tool for specific file types
pattern_search_tool = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["."],
  file_extensions: [".rb"],
  max_results: 20
)

# Create a pattern analysis agent
pattern_agent = OpenAIAgents::Agent.new(
  name: "PatternAgent",
  instructions: "You are a code pattern analyst. Use file search to find coding patterns, anti-patterns, and best practices in Ruby code.",
  model: "gpt-4o"
)

# Add pattern search tool
pattern_agent.add_tool(pattern_search_tool)

# Create runner
pattern_runner = OpenAIAgents::Runner.new(agent: pattern_agent)

# Test pattern search
begin
  pattern_messages = [{
    role: "user",
    content: "Find all Ruby files that use metaprogramming patterns like define_method or method_missing."
  }]

  pattern_result = pattern_runner.run(pattern_messages)
  puts "Pattern search result: #{pattern_result.final_output}"
rescue StandardError => e
  puts "Pattern search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 9: DOCUMENTATION SEARCH
# ============================================================================

puts "9. Documentation search:"

# Create a documentation search tool
doc_search_tool = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["."],
  file_extensions: [".md", ".txt", ".rst", ".adoc"],
  max_results: 10
)

# Create a documentation assistant
doc_agent = OpenAIAgents::Agent.new(
  name: "DocAgent",
  instructions: "You are a documentation assistant. Help users find and analyze documentation files in their projects.",
  model: "gpt-4o"
)

# Add documentation search tool
doc_agent.add_tool(doc_search_tool)

# Create runner
doc_runner = OpenAIAgents::Runner.new(agent: doc_agent)

# Test documentation search
begin
  doc_messages = [{
    role: "user",
    content: "Find all documentation that explains how to use the examples in this project."
  }]

  doc_result = doc_runner.run(doc_messages)
  puts "Documentation search result: #{doc_result.final_output}"
rescue StandardError => e
  puts "Documentation search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 10: HOSTED FILE SEARCH (OPENAI API)
# ============================================================================

puts "10. Hosted file search (OpenAI API):"

# Note: This would require file uploads to OpenAI and API key
if ENV["OPENAI_API_KEY"]
  puts "Hosted file search would require uploading files to OpenAI first."
  puts "This is useful for large-scale document search with semantic understanding."
  
  # Example of how to create a hosted file search tool
  hosted_tool = OpenAIAgents::Tools::HostedFileSearchTool.new(
    file_ids: [],  # Would contain OpenAI file IDs
    ranking_options: nil
  )
  
  puts "Hosted file search tool created (no files uploaded for this example)."
else
  puts "Hosted file search requires OPENAI_API_KEY environment variable."
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== File Search Tool Configuration ==="
puts "Local search paths: #{file_search_tool.instance_variable_get(:@search_paths)}"
puts "File extensions filter: #{file_search_tool.instance_variable_get(:@file_extensions)}"
puts "Maximum results: #{file_search_tool.instance_variable_get(:@max_results)}"
puts "Cache enabled: Yes (for performance)"
puts "Binary file detection: Yes (skips binary files)"
puts "Large file limit: 10MB (larger files skipped)"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key File Search Tool Features:"
puts "1. Content search with regex pattern matching"
puts "2. Filename search with pattern filtering"
puts "3. Combined search (both content and filename)"
puts "4. File extension filtering"
puts "5. Binary file detection and skipping"
puts "6. File caching for performance"
puts "7. Context-aware results with line numbers"
puts "8. Large file handling and limits"
puts "9. Both local and hosted search options"
puts "10. Integration with multi-tool workflows"
puts
puts "Search Types:"
puts "- content: Search within file contents"
puts "- filename: Search file names only"
puts "- both: Search both content and filenames"
puts
puts "Best Practices:"
puts "- Use specific file extensions to improve performance"
puts "- Set appropriate max_results for your use case"
puts "- Configure search paths to focus on relevant directories"
puts "- Use pattern matching for precise searches"
puts "- Consider file size limits for large repositories"
puts "- Implement caching for frequently searched files"
puts "- Handle binary files and encoding issues gracefully"
puts "- Provide context with line numbers and surrounding code"
puts
puts "Use Cases:"
puts "- Code review and analysis"
puts "- Documentation search and maintenance"
puts "- Configuration management"
puts "- Security auditing and compliance"
puts "- Development workflow automation"
puts "- Pattern analysis and refactoring"
puts "- Dependency tracking and management"
puts "- Knowledge base search and navigation"