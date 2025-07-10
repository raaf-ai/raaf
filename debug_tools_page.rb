#!/usr/bin/env ruby
# Script to debug why tools page is empty
# Run with: rails runner debug_tools_page.rb

puts "Debugging Tools Page..."
puts "=" * 60

# Check total spans
total_spans = OpenAIAgents::Tracing::SpanRecord.count
puts "Total spans in database: #{total_spans}"

# Check tool spans specifically
tool_spans = OpenAIAgents::Tracing::SpanRecord.by_kind("tool")
puts "Tool spans count: #{tool_spans.count}"

if tool_spans.any?
  puts "\nSample tool spans:"
  tool_spans.limit(5).each do |span|
    puts "\n" + ("-" * 40)
    puts "Span ID: #{span.span_id}"
    puts "Name: #{span.name}"
    puts "Kind: #{span.kind}"
    puts "Status: #{span.status}"
    puts "Attributes: #{span.span_attributes.inspect}"

    # Check if function data exists
    if span.span_attributes&.dig("function")
      puts "Function data found:"
      puts "  Name: #{span.span_attributes.dig("function", "name")}"
      puts "  Input: #{span.span_attributes.dig("function", "input")}"
      puts "  Output: #{span.span_attributes.dig("function", "output")&.truncate(100)}"
    else
      puts "No function data in attributes!"
    end
  end
else
  puts "\nNo tool spans found in database!"

  # Let's check what kinds of spans we do have
  puts "\nSpan kinds in database:"
  kind_counts = OpenAIAgents::Tracing::SpanRecord.group(:kind).count
  kind_counts.each do |kind, count|
    puts "  #{kind}: #{count} spans"
  end

  # Check if there are any spans that might be tools but have wrong kind
  puts "\nChecking for spans with function attributes but wrong kind:"
  spans_with_function = OpenAIAgents::Tracing::SpanRecord
                        .where("span_attributes::text LIKE '%function%'")
                        .where.not(kind: "tool")
                        .limit(5)

  if spans_with_function.any?
    puts "Found #{spans_with_function.count} spans with function data but not marked as 'tool':"
    spans_with_function.each do |span|
      puts "  - #{span.span_id} (kind: #{span.kind})"
      puts "    Function: #{span.span_attributes.dig("function", "name")}"
    end
  end
end

# Check the SQL query that the tools page would use
puts "\n" + ("=" * 60)
puts "SQL Query Check:"
puts "-" * 40

# Simulate the controller query
query = OpenAIAgents::Tracing::SpanRecord.includes(:trace)
                                         .by_kind("tool")
                                         .recent

puts "Query SQL: #{query.to_sql}"
puts "Query count: #{query.count}"

# Check if there's an issue with the recent scope
puts "\nWithout 'recent' scope: #{OpenAIAgents::Tracing::SpanRecord.by_kind("tool").count}"

# Check raw database
puts "\n" + ("=" * 60)
puts "Raw Database Check:"
result = ActiveRecord::Base.connection.execute(
  "SELECT COUNT(*) FROM openai_agents_tracing_spans WHERE kind = 'tool'"
)
puts "Raw SQL count: #{result.first["count"]}"

# Check pagination
puts "\n" + ("=" * 60)
puts "Pagination Check:"
page = 1
per_page = 50
paginated = query.offset((page - 1) * per_page).limit(per_page)
puts "Paginated count: #{paginated.count}"

puts "\n" + ("=" * 60)
puts "Recommendations:"
puts "1. If no tool spans exist, you need to make AI calls that use tools"
puts "2. Ensure tools are being traced with kind='tool'"
puts "3. Check that the OpenAI-hosted tools fix is working"
puts "4. Try creating a test tool call to verify tracing"
