#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf-dsl"
require "fileutils"

# Example: Flexible Prompt Resolution System
#
# This example demonstrates the configurable prompt resolution framework
# that supports multiple prompt formats:
# 1. Phlex-style prompt classes
# 2. File-based prompts with automatic format detection:
#    - Plain Markdown (.md, .markdown) with {{variable}} interpolation
#    - ERB templates (.md.erb, .markdown.erb) with full Ruby capabilities

# Setup example prompt files
def setup_example_files
  FileUtils.mkdir_p("prompts")

  # Create a simple markdown prompt
  File.write("prompts/customer_service.md", <<~MD)
    ---
    id: customer-service
    version: 1.0
    category: support
    ---
    # System
    You are a helpful customer service representative for {{company_name}}.
    Your tone should be {{tone}} and professional.

    # User
    Please help the customer with their {{issue_type}} issue.
  MD

  # Create an ERB template prompt
  File.write("prompts/analysis.md.erb", <<~ERB)
    ---
    id: data-analysis
    version: 2.0
    ---
    # System
    You are a data analyst specializing in <%= domain %> analysis.

    Your expertise includes:
    <% skills.each do |skill| %>
    - <%= skill %>
    <% end %>

    # User
    Analyze the following <%= data_type %> data:

    <%= code_block(data, "json") %>

    Focus on these aspects:
    <%= numbered_list(analysis_points) %>
  ERB

  puts "✅ Created example prompt files in prompts/"
end

# Example 1: Configure the prompt resolution system
puts "🔧 CONFIGURING PROMPT RESOLUTION SYSTEM"
puts "=" * 60

RAAF::DSL.configure_prompts do |config|
  # Add search paths
  config.add_path "prompts"
  config.add_path "app/prompts" # Rails-style path

  # Configure resolver priorities (higher = checked first)
  config.enable_resolver :file, priority: 100     # File resolver handles .md, .md.erb, etc.
  config.enable_resolver :phlex, priority: 10     # Phlex classes

  puts "Configured resolvers:"
  puts "- File resolver (handles .md, .md.erb, .markdown) (priority: 100)"
  puts "- Phlex classes (priority: 10)"
end

# Example 2: Define a Phlex-style prompt class
class ResearchPrompt < RAAF::DSL::Prompts::Base

  def prompt_id
    "research-assistant"
  end

  def system
    <<~SYSTEM
      You are a research assistant specializing in #{@topic}.
      Research depth: #{@depth}
      Available sources: #{@sources.join(', ')}
    SYSTEM
  end

  def user
    "Please provide a comprehensive analysis of #{@topic}."
  end
end

# Example 3: Resolve prompts from different sources
puts "\n📄 RESOLVING PROMPTS FROM DIFFERENT SOURCES"
puts "=" * 60

# Setup example files
setup_example_files

# 3.1: Resolve from Phlex class
puts "\n1. Resolving from Phlex class:"
prompt1 = RAAF::DSL::Prompt.resolve(ResearchPrompt, topic: "AI Ethics", depth: "deep")
if prompt1
  puts "   ID: #{prompt1.id}"
  puts "   Messages: #{prompt1.messages.size} messages"
  puts "   First message preview: #{prompt1.messages.first[:content][0..50]}..."
end

# 3.2: Resolve from Markdown file (handled by file resolver)
puts "\n2. Resolving from Markdown file:"
prompt2 = RAAF::DSL::Prompt.resolve("customer_service.md",
                                    company_name: "ACME Corp",
                                    tone: "friendly",
                                    issue_type: "billing")
if prompt2
  puts "   ID: #{prompt2.id}"
  puts "   Version: #{prompt2.version}"
  puts "   Category: #{prompt2.metadata['category']}"
  puts "   System message preview: #{prompt2.messages.first[:content][0..60]}..."
end

# 3.3: Resolve from ERB template (also handled by file resolver)
puts "\n3. Resolving from ERB template:"
prompt3 = RAAF::DSL::Prompt.resolve("analysis.md.erb",
                                    domain: "financial",
                                    skills: ["Statistical Analysis", "Risk Assessment", "Forecasting"],
                                    data_type: "quarterly revenue",
                                    data: { q1: 1_000_000, q2: 1_200_000, q3: 1_100_000, q4: 1_500_000 },
                                    analysis_points: ["Growth trends", "Seasonal patterns", "Risk factors"])
if prompt3
  puts "   ID: #{prompt3.id}"
  puts "   Version: #{prompt3.version}"
  puts "   Messages contain: #{prompt3.messages.map { |m| m[:role] }.join(', ')}"
end

# Example 4: Custom resolver
puts "\n🔌 CREATING CUSTOM RESOLVER"
puts "=" * 60

class YamlPromptResolver < RAAF::DSL::PromptResolver
  def initialize(**options)
    super(name: :yaml, **options)
    @paths = options[:paths] || ["prompts"]
  end

  def can_resolve?(prompt_spec)
    prompt_spec.is_a?(String) && prompt_spec.end_with?(".yml", ".yaml")
  end

  def resolve(prompt_spec, context = {})
    return nil unless can_resolve?(prompt_spec)

    # Find the YAML file
    file_path = @paths.map { |p| File.join(p, prompt_spec) }
                      .find { |f| File.exist?(f) }

    return nil unless file_path

    # Load and parse YAML
    data = YAML.safe_load_file(file_path)

    # Build prompt
    RAAF::DSL::Prompt.new(
      id: data["id"] || File.basename(file_path, ".*"),
      version: data["version"],
      messages: [
        { role: "system", content: interpolate(data["system"], context) },
        { role: "user", content: interpolate(data["user"], context) }
      ].compact
    )
  end

  private

  def interpolate(text, context)
    return nil unless text

    text.gsub(/\{\{(\w+)\}\}/) { |m| context[::Regexp.last_match(1).to_sym] || m }
  end
end

# Register the custom resolver
RAAF::DSL.configure_prompts do |config|
  config.register_resolver :yaml, YamlPromptResolver, priority: 75
end

# Create example YAML prompt
File.write("prompts/custom.yml", <<~YAML)
  id: custom-assistant
  version: 1.0
  system: "You are a {{role}} assistant."
  user: "Help me with {{task}}."
YAML

# Use the custom resolver
puts "Created and registered custom YAML resolver"
prompt4 = RAAF::DSL::Prompt.resolve("custom.yml",
                                    role: "technical",
                                    task: "debugging Ruby code")
if prompt4
  puts "Resolved YAML prompt:"
  puts "   ID: #{prompt4.id}"
  puts "   System: #{prompt4.messages.first[:content]}"
end

# Example 5: Using prompts with agents
puts "\n🤖 USING PROMPTS WITH AGENTS"
puts "=" * 60

# Create an agent using prompt resolution
begin
  require "raaf-core" # This would be the core gem

  # Method 1: Resolve prompt separately
  prompt = RAAF::DSL::Prompt.resolve("customer_service.md",
                                     company_name: "Tech Solutions Inc",
                                     tone: "empathetic",
                                     issue_type: "technical")

  agent = RAAF::Agent.new(
    name: "SupportAgent",
    instructions: prompt.messages.map { |m| m[:content] }.join("\n\n"),
    model: "gpt-4o"
  )

  puts "Created agent with resolved prompt"
  puts "Agent instructions preview: #{agent.instructions[0..100]}..."
rescue LoadError
  puts "Note: raaf-core gem not available in this example"
  puts "In a real application, you would use resolved prompts with RAAF agents"
end

# Example 6: Dynamic prompt selection
puts "\n🎯 DYNAMIC PROMPT SELECTION"
puts "=" * 60

def get_prompt_for_scenario(scenario)
  case scenario
  when :research
    RAAF::DSL::Prompt.resolve(ResearchPrompt,
                              topic: "Climate Change",
                              depth: "comprehensive")
  when :support
    RAAF::DSL::Prompt.resolve("customer_service.md",
                              company_name: "GlobalTech",
                              tone: "professional",
                              issue_type: "account")
  when :analysis
    RAAF::DSL::Prompt.resolve("analysis.md.erb",
                              domain: "market",
                              skills: ["Trend Analysis"],
                              data_type: "sales",
                              data: { jan: 100, feb: 120 },
                              analysis_points: ["Monthly growth"])
  end
end

%i[research support analysis].each do |scenario|
  prompt = get_prompt_for_scenario(scenario)
  puts "Scenario '#{scenario}' -> Prompt ID: #{prompt&.id || 'not found'}"
end

# Cleanup
puts "\n🧹 Cleaning up example files..."
FileUtils.rm_rf("prompts")
puts "✅ Example complete!"

puts "\n📚 KEY TAKEAWAYS:"
puts "1. Configure multiple prompt resolvers with priorities"
puts "2. Unified file resolver handles .md, .md.erb, and more"
puts "3. Automatic format detection based on file extension"
puts "4. Plain markdown uses {{variable}} interpolation"
puts "5. ERB templates have full Ruby capabilities and helpers"
puts "6. Create custom resolvers for any format"
puts "7. Integrate seamlessly with RAAF agents"
puts "8. Extensible architecture for adding new formats"
