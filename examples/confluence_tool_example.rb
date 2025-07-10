#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/tools/confluence_tool"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Confluence Integration Tool Example ==="
puts

# NOTE: You'll need Confluence credentials
CONFLUENCE_URL = ENV["CONFLUENCE_URL"] || "https://demo.atlassian.net"
CONFLUENCE_USERNAME = ENV["CONFLUENCE_USERNAME"] || "demo"
CONFLUENCE_API_TOKEN = ENV["CONFLUENCE_API_TOKEN"] || "demo"

if CONFLUENCE_USERNAME == "demo"
  puts "Note: This example is running in demo mode. To use real Confluence:"
  puts "1. Create an API token at: https://id.atlassian.com/manage/api-tokens"
  puts "2. Set environment variables:"
  puts "   export CONFLUENCE_URL='https://your-domain.atlassian.net'"
  puts "   export CONFLUENCE_USERNAME='your-email@example.com'"
  puts "   export CONFLUENCE_API_TOKEN='your-api-token'"
  puts
  puts "Running with simulated responses..."
  puts
end

# Create Confluence tool
confluence_tool = OpenAIAgents::Tools::ConfluenceTool.new(
  url: CONFLUENCE_URL,
  username: CONFLUENCE_USERNAME,
  api_token: CONFLUENCE_API_TOKEN,
  name: "confluence",
  description: "Manage Confluence wiki pages and content"
)

# Create an agent with Confluence capabilities
agent = OpenAIAgents::Agent.new(
  name: "WikiAssistant",
  model: "gpt-4o",
  instructions: <<~INSTRUCTIONS
    You are a helpful Confluence wiki assistant.
    
    You can help with:
    - Creating and organizing documentation pages
    - Searching for existing content
    - Managing page hierarchies
    - Adding and organizing labels
    - Creating spaces for projects
    - Formatting content properly
    
    When working with Confluence:
    - Use clear, descriptive page titles
    - Organize content hierarchically with parent/child pages
    - Apply appropriate labels for discoverability
    - Use Confluence storage format for rich content
    - Include relevant metadata and descriptions
    
    Best practices:
    - Check if content already exists before creating
    - Link related pages together
    - Use templates for consistency
    - Keep pages focused on single topics
    - Update rather than duplicate content
  INSTRUCTIONS
)

# Add Confluence tool to agent
agent.add_tool(confluence_tool)

# Create runner
runner = OpenAIAgents::Runner.new(agent: agent)

# Example 1: List available spaces
puts "Example 1: Listing Confluence Spaces"
puts "-" * 50
result = runner.run("Show me all available Confluence spaces")
puts result.messages.last[:content]
puts

# Example 2: Search for content
puts "Example 2: Searching for Documentation"
puts "-" * 50
result = runner.run("Search for any pages about 'getting started' or 'installation'")
puts result.messages.last[:content]
puts

# Example 3: Create documentation structure
puts "Example 3: Creating Documentation Structure"
puts "-" * 50
result = runner.run(<<~PROMPT)
  Help me create a documentation structure for a new project:
  - Main project page titled "Ruby Agent Framework"
  - Child pages for: Installation, Quick Start, API Reference, Examples
  - Add appropriate labels
PROMPT
puts result.messages.last[:content]
puts

# Example 4: Page content management
puts "Example 4: Managing Page Content"
puts "-" * 50
result = runner.run(<<~PROMPT)
  Create a well-formatted page with:
  - Title: "API Authentication Guide"
  - Sections: Overview, API Keys, OAuth Flow, Best Practices
  - Include a table of contents
  - Add code examples for each auth method
PROMPT
puts result.messages.last[:content]
puts

# Direct tool usage examples
puts "\n=== Direct Tool Usage Examples ==="
puts

# List spaces
puts "Listing spaces:"
spaces_result = confluence_tool.call({
                                       action: "list_spaces",
                                       limit: 10
                                     })
puts "Found #{spaces_result[:count]} spaces:"
spaces_result[:spaces]&.each do |space|
  puts "  - [#{space[:key]}] #{space[:name]}"
end
puts

# Search content
puts "\nSearching content:"
search_result = confluence_tool.call({
                                       action: "search_content",
                                       query: "type=page AND text ~ \"documentation\"",
                                       limit: 5
                                     })
puts "Found #{search_result[:count]} results"
search_result[:results]&.each do |result|
  puts "  - #{result[:title]} (#{result[:space]})"
end
puts

# Create a page (demo)
puts "\nCreating a page (demo):"
if CONFLUENCE_USERNAME == "demo"
  puts "  Would create: 'Quick Reference Guide'"
  puts "  In space: PROJ"
  puts "  With formatted content"
else
  create_result = confluence_tool.call({
                                         action: "create_page",
                                         space_key: "PROJ", # Replace with your space key
                                         title: "Quick Reference Guide",
                                         content: <<~HTML
                                           <h2>Overview</h2>
                                           <p>This is a quick reference guide for common tasks.</p>
                                           
                                           <h2>Common Commands</h2>
                                           <table>
                                             <tr>
                                               <th>Command</th>
                                               <th>Description</th>
                                             </tr>
                                             <tr>
                                               <td><code>agent.run()</code></td>
                                               <td>Execute agent with input</td>
                                             </tr>
                                             <tr>
                                               <td><code>agent.add_tool()</code></td>
                                               <td>Add a tool to agent</td>
                                             </tr>
                                           </table>
                                           
                                           <h2>Examples</h2>
                                           <ac:structured-macro ac:name="code">
                                             <ac:parameter ac:name="language">ruby</ac:parameter>
                                             <ac:plain-text-body><![CDATA[
                                               agent = OpenAIAgents::Agent.new(
                                                 name: "Assistant",
                                                 model: "gpt-4o"
                                               )
                                               result = agent.run("Hello!")
                                             ]]></ac:plain-text-body>
                                           </ac:structured-macro>
                                         HTML
                                       })
  puts "Created page: #{create_result[:url]}" if create_result[:success]
end
puts

# Advanced examples with agent
puts "\n=== Advanced Agent Examples ==="
puts

# Example 5: Knowledge base organization
puts "Example 5: Organizing Knowledge Base"
puts "-" * 50
result = runner.run(<<~PROMPT)
  I need to reorganize our knowledge base:
  1. Find all pages related to "troubleshooting"
  2. Suggest a better structure
  3. Create a main troubleshooting page
  4. Plan how to organize sub-pages by category
PROMPT
puts result.messages.last[:content]
puts

# Example 6: Content migration
puts "Example 6: Content Migration Planning"
puts "-" * 50
result = runner.run(<<~PROMPT)
  Help me migrate content from multiple pages:
  1. Find all pages with "deprecated" label
  2. Create an archive space if needed
  3. Move deprecated content to archive
  4. Update links in remaining pages
PROMPT
puts result.messages.last[:content]
puts

# Example 7: Documentation templates
puts "Example 7: Creating Documentation Templates"
puts "-" * 50
result = runner.run(<<~PROMPT)
  Create a template for API endpoint documentation with:
  - Endpoint URL and method
  - Parameters table
  - Request/response examples
  - Error codes
  - Rate limiting info
PROMPT
puts result.messages.last[:content]
puts

# Example 8: Collaborative workflows
puts "Example 8: Setting Up Review Workflows"
puts "-" * 50
result = runner.run(<<~PROMPT)
  Set up a documentation review workflow:
  1. Create a "Draft" label
  2. Create a "Ready for Review" label
  3. Create a "Approved" label
  4. Create a review checklist page
  5. Add instructions for reviewers
PROMPT
puts result.messages.last[:content]
puts

# Confluence-specific features
puts "\n=== Confluence Storage Format Examples ==="
puts "-" * 50

# Confluence storage format examples
storage_examples = {
  "Rich Text" => <<~XML,
    <p>This is <strong>bold</strong> and <em>italic</em> text.</p>
    <p>This is <u>underlined</u> and <s>strikethrough</s> text.</p>
  XML
  
  "Code Block" => <<~XML,
    <ac:structured-macro ac:name="code">
      <ac:parameter ac:name="language">ruby</ac:parameter>
      <ac:parameter ac:name="theme">RDark</ac:parameter>
      <ac:parameter ac:name="linenumbers">true</ac:parameter>
      <ac:plain-text-body><![CDATA[
        def hello_world
          puts "Hello, World!"
        end
      ]]></ac:plain-text-body>
    </ac:structured-macro>
  XML
  
  "Info Panel" => <<~XML,
    <ac:structured-macro ac:name="info">
      <ac:rich-text-body>
        <p>This is an informational message.</p>
      </ac:rich-text-body>
    </ac:structured-macro>
  XML
  
  "Table of Contents" => <<~XML,
    <ac:structured-macro ac:name="toc">
      <ac:parameter ac:name="maxLevel">3</ac:parameter>
    </ac:structured-macro>
  XML
  
  "Page Link" => <<~XML,
    <ac:link>
      <ri:page ri:content-title="Page Title" />
    </ac:link>
  XML
  
  "User Mention" => <<~XML
    <ac:link>
      <ri:user ri:userkey="user-key-here" />
    </ac:link>
  XML
}

puts "Common Confluence storage format patterns:"
storage_examples.each do |name, example|
  puts "\n#{name}:"
  puts example
end

# CQL (Confluence Query Language) examples
puts "\n=== CQL Search Examples ==="
puts "-" * 50

cql_examples = {
  "Pages created today" => 'type = page AND created = now("0d")',
  "Pages by label" => 'type = page AND label = "documentation"',
  "Pages in space" => 'type = page AND space = "PROJ"',
  "Recently updated" => 'type = page AND lastmodified > now("-7d")',
  "Pages by creator" => "type = page AND creator = currentUser()",
  "Pages with attachments" => "type = page AND attachment.title is not EMPTY",
  "Unresolved comments" => "type = comment AND resolved = false",
  "Pages containing text" => 'type = page AND text ~ "search term"'
}

puts "Useful CQL queries:"
cql_examples.each do |description, query|
  puts "  #{description}:"
  puts "    #{query}"
end
puts

# Best practices
puts "\nConfluence Integration Best Practices:"
puts "-" * 50
puts <<~PRACTICES
  1. Authentication:
     - Use API tokens, not passwords
     - Store credentials securely
     - Use environment variables
     - Rotate tokens regularly
  
  2. Content Organization:
     - Use clear page hierarchies
     - Apply consistent labeling
     - Create space blueprints
     - Use page templates
  
  3. Content Creation:
     - Use storage format for rich content
     - Include metadata (labels, descriptions)
     - Link related content
     - Version significant changes
  
  4. Search Optimization:
     - Use descriptive titles
     - Add relevant labels
     - Include keywords in content
     - Use CQL for precise searches
  
  5. Performance:
     - Batch operations when possible
     - Use expansion parameters wisely
     - Cache frequently accessed content
     - Limit search results
  
  6. Collaboration:
     - Use @mentions for notifications
     - Add comments for discussions
     - Track page watchers
     - Use tasks for action items
  
  7. Automation Ideas:
     - Auto-generate release notes
     - Sync documentation from code
     - Create weekly reports
     - Archive old content
PRACTICES

puts "\nConfluence tool example completed!"
