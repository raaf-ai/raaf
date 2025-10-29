# RAAF Continuation Examples

Working code examples for the continuation feature across CSV, Markdown, and JSON formats.

## CSV Examples

### Example 1: Generate and Parse Large CSV

```ruby
class CompanyListGenerator < RAAF::DSL::Agent
  agent_name "CompanyListGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :csv
    max_attempts 20
  end

  static_instructions <<~PROMPT
    Generate a CSV with these columns:
    company_id, company_name, industry, annual_revenue, employee_count,
    founded_year, headquarters, website, description

    Include 500+ rows of realistic company data.
    Make each company unique and detailed.
  PROMPT
end

# Usage
agent = CompanyListGenerator.new
result = agent.run("Generate list of enterprise software companies")

# Parse and process CSV
require "csv"

csv_data = CSV.parse(result[:content], headers: true)
puts "Generated #{csv_data.length} companies"

# Access specific columns
csv_data.each do |row|
  puts "#{row['company_name']}: #{row['industry']} (#{row['employee_count']} employees)"
end

# Check continuation
if result[:metadata][:merge_success]
  puts "✅ All data successfully merged from #{result[:metadata][:chunk_count]} chunks"
else
  puts "⚠️ Partial data: #{result[:metadata][:merge_error]}"
end
```

### Example 2: Sales Data CSV with Error Handling

```ruby
class SalesDataGenerator < RAAF::DSL::Agent
  agent_name "SalesDataGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :csv
    max_attempts 15
    on_failure :return_partial  # Accept partial results
  end

  static_instructions <<~PROMPT
    Generate quarterly sales data as CSV:
    date, product_id, product_name, quantity_sold, revenue, region, sales_rep

    Generate 1000+ rows spanning 4 quarters.
    Include realistic sales numbers and regional variations.
  PROMPT
end

# Usage with error handling
agent = SalesDataGenerator.new
result = agent.run("Generate 2024 sales data")

begin
  csv_data = CSV.parse(result[:content], headers: true)

  # Calculate summary
  total_revenue = csv_data.sum { |row| row['revenue'].to_f }
  total_quantity = csv_data.sum { |row| row['quantity_sold'].to_i }

  puts "Total Revenue: $#{total_revenue.round(2)}"
  puts "Total Quantity: #{total_quantity}"

  # Group by region
  by_region = csv_data.group_by { |row| row['region'] }
  by_region.each do |region, rows|
    region_revenue = rows.sum { |r| r['revenue'].to_f }
    puts "  #{region}: $#{region_revenue.round(2)}"
  end

rescue CSV::ParsingError => e
  if result[:metadata][:merge_success]
    puts "CSV parsing error: #{e.message}"
  else
    puts "Partial data available, merge incomplete"
    puts "Error: #{result[:metadata][:merge_error]}"
  end
end
```

### Example 3: Customer Records with Quoted Fields

```ruby
class CustomerRecordsGenerator < RAAF::DSL::Agent
  agent_name "CustomerRecordsGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :csv
    max_attempts 10
  end

  static_instructions <<~PROMPT
    Generate customer records CSV with these fields:
    id, first_name, last_name, email, phone, company, address, notes

    Important: Some fields contain commas or special characters.
    Properly quote fields that contain commas.
    Generate 300+ customer records with realistic variation.
  PROMPT
end

# Usage
agent = CustomerRecordsGenerator.new
result = agent.run("Generate sample customer database")

require "csv"

# Continuation handles split quoted fields automatically
csv_data = CSV.parse(result[:content], headers: true)

# Export to file
File.open("customers.csv", "w") do |f|
  f.write(result[:content])
end

puts "Exported #{csv_data.length} customer records to customers.csv"

# Verify data integrity
csv_data.each do |row|
  next if row['email'].to_s.include?('@')
  puts "⚠️  Invalid email: #{row['email']}"
end
```

## Markdown Examples

### Example 1: Generate Comprehensive Documentation

```ruby
class APIDocumentationGenerator < RAAF::DSL::Agent
  agent_name "APIDocumentationGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :markdown
    max_attempts 20
  end

  static_instructions <<~PROMPT
    Generate comprehensive API documentation with:

    # Heading structure:
    - Main title
    - Overview section
    - Authentication section with examples
    - Multiple endpoint sections (GET, POST, PUT, DELETE)
    - Request/response examples for each
    - Error codes and handling
    - Rate limiting info
    - Best practices

    # Include:
    - Code examples (Ruby, Python, JavaScript)
    - Tables for parameters and responses
    - Links and cross-references
    - Warnings and tips

    Make it detailed and thoroughly documented (5000+ words).
  PROMPT
end

# Usage
agent = APIDocumentationGenerator.new
result = agent.run("Document the ProspectsRadar API")

# Save documentation
File.write("API_DOCUMENTATION.md", result[:content])

# Verify merge success
if result[:metadata][:merge_success]
  puts "✅ Documentation generated successfully"
  puts "   Headings: #{result[:metadata][:heading_count]}"
  puts "   Tables: #{result[:metadata][:table_count]}"
  puts "   Size: #{result[:metadata][:final_content_size]} bytes"
else
  puts "⚠️ Partial documentation generated"
end
```

### Example 2: Market Analysis Report

```ruby
class MarketAnalysisReportGenerator < RAAF::DSL::Agent
  agent_name "MarketAnalysisReportGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :markdown
    max_attempts 15
  end

  static_instructions <<~PROMPT
    Generate a detailed market analysis report with:

    # Structure:
    1. Executive Summary
    2. Market Overview and Size
    3. Growth Trends and Projections
    4. Competitive Landscape (table comparing competitors)
    5. Customer Segments and Demographics
    6. Technology Trends
    7. Regulatory Environment
    8. Key Success Factors
    9. Risks and Challenges
    10. Recommendations

    # Include:
    - Multiple tables with market data
    - Key metrics and statistics
    - Formatted lists with bullet points
    - Key insights highlighted as blockquotes
    - Code examples where relevant

    Target audience: Executive team and investors
    Make it professional and data-driven (3000+ words).
  PROMPT
end

# Usage
agent = MarketAnalysisReportGenerator.new
result = agent.run("Analyze the AI/ML market for enterprise software")

# Process and save
markdown_content = result[:content]

# Extract key sections
lines = markdown_content.lines

# Find headers
headers = lines.grep(/^#+\s/).map { |line| line.strip }
puts "Report sections: #{headers.length}"
headers.each { |header| puts "  #{header}" }

# Count tables
tables = lines.grep(/^\|/).length
puts "Tables included: #{tables}"

# Save to file
File.write("market_analysis.md", markdown_content)
puts "Report saved to market_analysis.md"
```

### Example 3: Technical Specification

```ruby
class TechnicalSpecGenerator < RAAF::DSL::Agent
  agent_name "TechnicalSpecGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :markdown
    max_attempts 18
  end

  static_instructions <<~PROMPT
    Generate a technical specification document with:

    ## Sections:
    1. Overview and Scope
    2. Architecture Diagram (ASCII art)
    3. System Components (table)
    4. Data Models (with examples)
    5. API Endpoints (with code samples)
    6. Security Considerations
    7. Performance Requirements
    8. Testing Strategy
    9. Deployment Plan
    10. Maintenance and Support

    ## Format:
    - Use proper heading hierarchy
    - Include code blocks with language highlighting
    - Create comparison tables
    - Add important notes as blockquotes
    - Include architecture diagrams

    Technical detail level: High (for engineers)
    Length: Comprehensive (4000+ words)
  PROMPT
end

# Usage
agent = TechnicalSpecGenerator.new
result = agent.run("Create tech spec for real-time analytics engine")

# Parse and validate
content = result[:content]

# Extract code blocks
code_blocks = content.scan(/```(\w+)\n(.*?)```/m)
puts "Code examples: #{code_blocks.length}"
code_blocks.each do |lang, code|
  puts "  Language: #{lang || 'unknown'}"
  puts "  Lines: #{code.lines.length}"
end

# Save spec
File.write("TECHNICAL_SPEC.md", content)
```

## JSON Examples

### Example 1: Generate Product Catalog

```ruby
class ProductCatalogGenerator < RAAF::DSL::Agent
  agent_name "ProductCatalogGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :json
    max_attempts 15
    on_failure :return_partial
  end

  static_instructions <<~PROMPT
    Generate a JSON array of products with this structure:

    [
      {
        "product_id": "string",
        "name": "string",
        "category": "string",
        "description": "string",
        "price": number,
        "currency": "USD",
        "stock": integer,
        "rating": number (0-5),
        "tags": ["string"],
        "specifications": {
          "dimension": "string",
          "weight": "string",
          "color": "string"
        }
      }
    ]

    Generate 200+ products with realistic details.
    Include variety in categories, prices, and specifications.
  PROMPT
end

# Usage
agent = ProductCatalogGenerator.new
result = agent.run("Generate e-commerce product catalog")

begin
  # Parse JSON
  products = JSON.parse(result[:content])
  puts "Generated #{products.length} products"

  # Analyze
  avg_price = products.sum { |p| p['price'].to_f } / products.length
  avg_rating = products.sum { |p| p['rating'].to_f } / products.length

  puts "Average price: $#{avg_price.round(2)}"
  puts "Average rating: #{avg_rating.round(2)}/5"

  # Group by category
  by_category = products.group_by { |p| p['category'] }
  puts "\nProducts by category:"
  by_category.each do |category, items|
    puts "  #{category}: #{items.length} products"
  end

  # Save catalog
  File.write("catalog.json", JSON.pretty_generate(products))
  puts "\nCatalog saved to catalog.json"

rescue JSON::ParsingError => e
  puts "JSON parsing error: #{e.message}"
  if !result[:metadata][:merge_success]
    puts "Merge incomplete - may have syntax errors"
    puts "Error: #{result[:metadata][:merge_error]}"
  end
end
```

### Example 2: User Database with Nested Data

```ruby
class UserDatabaseGenerator < RAAF::DSL::Agent
  agent_name "UserDatabaseGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :json
    max_attempts 12
  end

  static_instructions <<~PROMPT
    Generate a JSON array of user objects with nested data:

    [
      {
        "id": integer,
        "username": "string",
        "email": "string",
        "full_name": "string",
        "created_at": "ISO8601 timestamp",
        "profile": {
          "bio": "string",
          "location": "string",
          "website": "string"
        },
        "preferences": {
          "theme": "light|dark",
          "notifications": boolean,
          "language": "string"
        },
        "roles": ["string"],
        "metadata": {
          "last_login": "ISO8601 timestamp",
          "login_count": integer,
          "api_key_count": integer
        }
      }
    ]

    Generate 150+ realistic users with varied profiles and preferences.
  PROMPT
end

# Usage
agent = UserDatabaseGenerator.new
result = agent.run("Generate sample user database")

require "json"

users = JSON.parse(result[:content])
puts "Generated #{users.length} users"

# Filter by role
admins = users.select { |u| u['roles'].include?('admin') }
puts "Admin users: #{admins.length}"

# Find active users
active_users = users.select { |u|
  Time.parse(u['metadata']['last_login']) > Time.now - 7.days
}
puts "Active in last 7 days: #{active_users.length}"

# Save as JSON
File.write("users.json", JSON.pretty_generate(users))

# Also save as CSV for spreadsheet
require "csv"
CSV.open("users.csv", "w") do |csv|
  csv << ["ID", "Username", "Email", "Full Name", "Roles", "Theme", "Last Login"]
  users.each do |user|
    csv << [
      user['id'],
      user['username'],
      user['email'],
      user['full_name'],
      user['roles'].join(';'),
      user['preferences']['theme'],
      user['metadata']['last_login']
    ]
  end
end

puts "Exported to users.json and users.csv"
```

### Example 3: Config File Generation

```ruby
class ConfigurationGenerator < RAAF::DSL::Agent
  agent_name "ConfigurationGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :json
    max_attempts 10
  end

  static_instructions <<~PROMPT
    Generate a comprehensive application configuration JSON with:

    {
      "app": {
        "name": "string",
        "version": "string",
        "environment": "development|staging|production",
        "debug": boolean
      },
      "database": {
        "adapter": "postgresql",
        "host": "string",
        "port": integer,
        "username": "string",
        "password": "string",
        "pool": integer,
        "timeout": integer
      },
      "redis": {
        "url": "string",
        "timeout": integer
      },
      "logging": {
        "level": "debug|info|warn|error",
        "format": "json|plain",
        "file": "string"
      },
      "services": {
        "[service_name]": {
          "enabled": boolean,
          "api_key": "string",
          "endpoint": "string",
          "timeout": integer
        }
      },
      "features": {
        "[feature_name]": boolean
      }
    }

    Include realistic values for a production SaaS application.
  PROMPT
end

# Usage
agent = ConfigurationGenerator.new
result = agent.run("Generate production config for AI analytics platform")

config = JSON.parse(result[:content])

# Load into environment-specific config
ENV['DATABASE_URL'] = "postgresql://#{config['database']['username']}@#{config['database']['host']}"
ENV['REDIS_URL'] = config['redis']['url']

# Validate configuration
required_services = ['database', 'redis', 'logging']
required_services.each do |service|
  unless config[service]
    puts "❌ Missing required service: #{service}"
  end
end

# Output config info
puts "Configuration loaded:"
puts "  App: #{config['app']['name']} v#{config['app']['version']}"
puts "  Environment: #{config['app']['environment']}"
puts "  Database: #{config['database']['host']}:#{config['database']['port']}"
puts "  Logging: #{config['logging']['level']}"

# Save config
File.write("config.json", JSON.pretty_generate(config))
```

## Mixed Format Examples

### Example 1: Multi-Format Report Generation

```ruby
class MultiFormatReportGenerator
  def initialize(format)
    @format = format
  end

  def generate_agent_for_format
    case @format
    when :csv
      create_csv_agent
    when :markdown
      create_markdown_agent
    when :json
      create_json_agent
    end
  end

  private

  def create_csv_agent
    Class.new(RAAF::DSL::Agent) do
      agent_name "CSVReportAgent"
      model "gpt-4o"

      continuation_config do
        output_format :csv
        max_attempts 15
      end
    end
  end

  def create_markdown_agent
    Class.new(RAAF::DSL::Agent) do
      agent_name "MarkdownReportAgent"
      model "gpt-4o"

      continuation_config do
        output_format :markdown
        max_attempts 20
      end
    end
  end

  def create_json_agent
    Class.new(RAAF::DSL::Agent) do
      agent_name "JSONReportAgent"
      model "gpt-4o"

      continuation_config do
        output_format :json
        max_attempts 12
      end
    end
  end

  def generate
    agent_class = generate_agent_for_format
    agent = agent_class.new

    result = agent.run(prompt)

    {
      content: result[:content],
      format: @format,
      success: result[:metadata][:merge_success],
      metadata: result[:metadata]
    }
  end

  def prompt
    case @format
    when :csv
      "Generate 500+ companies in CSV format"
    when :markdown
      "Generate detailed market report in Markdown"
    when :json
      "Generate product catalog in JSON"
    end
  end
end

# Usage
reports = {
  csv: nil,
  markdown: nil,
  json: nil
}

reports.each_key do |format|
  generator = MultiFormatReportGenerator.new(format)
  reports[format] = generator.generate
end

# Process each report
reports.each do |format, report|
  puts "Format: #{format}"
  puts "  Success: #{report[:success]}"
  puts "  Size: #{report[:metadata][:final_content_size]} bytes"
  puts "  Chunks: #{report[:metadata][:chunk_count]}"
end
```

## Performance and Monitoring Examples

### Example 1: Monitor Continuation Performance

```ruby
class PerformanceMonitor
  def track_continuation(agent, query)
    start_time = Time.now

    result = agent.run(query)

    duration = Time.now - start_time
    metadata = result[:metadata]

    metrics = {
      query: query,
      format: metadata[:detected_format],
      chunks: metadata[:chunk_count],
      attempts: metadata[:continuation_attempts],
      success: metadata[:merge_success],
      duration_ms: (duration * 1000).round(2),
      final_size: metadata[:final_content_size],
      merge_time_ms: metadata[:merge_duration_ms]
    }

    log_metrics(metrics)
    metrics
  end

  private

  def log_metrics(metrics)
    puts """
    Performance Report:
    ═══════════════════════════════════════
    Format:        #{metrics[:format]}
    Chunks:        #{metrics[:chunks]}
    Continuation:  #{metrics[:attempts]} attempts
    Success:       #{metrics[:success] ? '✅' : '⚠️'}
    Duration:      #{metrics[:duration_ms]}ms
    Merge Time:    #{metrics[:merge_time_ms]}ms
    Final Size:    #{format_bytes(metrics[:final_size])}
    ═══════════════════════════════════════
    """
  end

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB']
    size = bytes.to_f
    unit_idx = 0

    while size >= 1024 && unit_idx < units.length - 1
      size /= 1024
      unit_idx += 1
    end

    "#{size.round(2)} #{units[unit_idx]}"
  end
end

# Usage
monitor = PerformanceMonitor.new
agent = CompanyListGenerator.new

metrics = monitor.track_continuation(agent, "Generate 500 companies")
```

## See Also

- **[Continuation Guide](./CONTINUATION_GUIDE.md)** - Configuration and best practices
- **[API Documentation](./API_DOCUMENTATION.md)** - Complete API reference
- **[Troubleshooting](./TROUBLESHOOTING.md)** - Common issues and solutions
