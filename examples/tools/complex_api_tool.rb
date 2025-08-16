#!/usr/bin/env ruby
# frozen_string_literal: true

# Complex API Tool Example
#
# This example demonstrates advanced features of the Tool::API class including:
# - Multiple HTTP methods
# - Authentication handling
# - Error recovery
# - Response transformation
# - Configuration management

require "raaf-core"
require "raaf-dsl"

# Advanced CRM API tool demonstrating complex API patterns
class CRMTool < RAAF::DSL::Tools::Tool::API
  # Configure the base endpoint
  endpoint ENV.fetch('CRM_API_URL', 'https://api.example-crm.com/v2')
  
  # Configure API authentication
  api_key ENV['CRM_API_KEY']
  
  # Set longer timeout for complex operations
  timeout 60
  
  # Configure default headers
  headers({
    "User-Agent" => "RAAF-CRM-Tool/2.0",
    "Accept" => "application/json",
    "Content-Type" => "application/json"
  })
  
  # Override tool metadata
  configure name: "crm_manager",
            description: "Comprehensive CRM tool for managing contacts, companies, and deals with advanced search and analytics"
  
  # Main entry point with action-based routing
  def call(action:, **params)
    # Validate API key is configured
    validate_api_key!
    
    # Route to appropriate action handler
    case action.downcase
    when "create_contact"
      create_contact(params)
    when "update_contact"
      update_contact(params)
    when "search_contacts"
      search_contacts(params)
    when "delete_contact"
      delete_contact(params)
    when "create_company"
      create_company(params)
    when "search_companies"
      search_companies(params)
    when "create_deal"
      create_deal(params)
    when "get_analytics"
      get_analytics(params)
    when "bulk_import"
      bulk_import(params)
    else
      { error: "Unknown action: #{action}", available_actions: available_actions }
    end
  rescue => e
    handle_error(e, action, params)
  end
  
  private
  
  # Contact management methods
  
  def create_contact(name:, email:, company: nil, phone: nil, **custom_fields)
    # Validate required fields
    validate_email!(email)
    
    contact_data = {
      name: name,
      email: email,
      company: company,
      phone: phone,
      custom_fields: custom_fields,
      created_at: Time.now.iso8601
    }.compact
    
    response = post("/contacts", 
                   json: contact_data,
                   headers: auth_headers)
    
    # Transform response for consistency
    transform_contact_response(response)
  end
  
  def update_contact(id:, **updates)
    validate_id!(id)
    
    # Add metadata
    update_data = updates.merge(
      updated_at: Time.now.iso8601,
      updated_by: "raaf_tool"
    )
    
    response = put("/contacts/#{id}", 
                  json: update_data,
                  headers: auth_headers)
    
    transform_contact_response(response)
  end
  
  def search_contacts(query: nil, limit: 25, offset: 0, filters: {}, sort_by: "created_at", sort_order: "desc")
    search_params = {
      limit: [limit, 100].min,  # Cap at 100
      offset: offset,
      sort_by: sort_by,
      sort_order: sort_order
    }
    
    # Add query if provided
    search_params[:q] = query if query && !query.strip.empty?
    
    # Add filters
    filters.each { |key, value| search_params["filter_#{key}"] = value }
    
    response = get("/contacts/search", 
                  params: search_params,
                  headers: auth_headers)
    
    transform_search_response(response, "contacts")
  end
  
  def delete_contact(id:)
    validate_id!(id)
    
    response = delete("/contacts/#{id}", headers: auth_headers)
    
    if response[:error]
      response
    else
      { success: true, id: id, deleted_at: Time.now.iso8601 }
    end
  end
  
  # Company management methods
  
  def create_company(name:, industry: nil, size: nil, website: nil, **custom_fields)
    company_data = {
      name: name,
      industry: industry,
      size: size,
      website: website,
      custom_fields: custom_fields,
      created_at: Time.now.iso8601
    }.compact
    
    response = post("/companies", 
                   json: company_data,
                   headers: auth_headers)
    
    transform_company_response(response)
  end
  
  def search_companies(query: nil, industry: nil, size: nil, limit: 25)
    search_params = {
      limit: [limit, 100].min,
      industry: industry,
      size: size
    }.compact
    
    search_params[:q] = query if query && !query.strip.empty?
    
    response = get("/companies/search", 
                  params: search_params,
                  headers: auth_headers)
    
    transform_search_response(response, "companies")
  end
  
  # Deal management methods
  
  def create_deal(title:, value:, stage:, contact_id: nil, company_id: nil, **custom_fields)
    deal_data = {
      title: title,
      value: value,
      stage: stage,
      contact_id: contact_id,
      company_id: company_id,
      custom_fields: custom_fields,
      created_at: Time.now.iso8601
    }.compact
    
    response = post("/deals", 
                   json: deal_data,
                   headers: auth_headers)
    
    transform_deal_response(response)
  end
  
  # Analytics methods
  
  def get_analytics(report_type:, date_range: "last_30_days", filters: {})
    analytics_params = {
      report_type: report_type,
      date_range: date_range,
      format: "json"
    }.merge(filters)
    
    response = get("/analytics/#{report_type}", 
                  params: analytics_params,
                  headers: auth_headers)
    
    transform_analytics_response(response)
  end
  
  # Bulk operations
  
  def bulk_import(data_type:, records:, update_existing: false, batch_size: 50)
    # Validate data type
    unless %w[contacts companies deals].include?(data_type)
      return { error: "Invalid data_type. Must be one of: contacts, companies, deals" }
    end
    
    # Process in batches
    results = []
    records.each_slice(batch_size) do |batch|
      batch_data = {
        data_type: data_type,
        records: batch,
        update_existing: update_existing,
        batch_id: SecureRandom.uuid
      }
      
      response = post("/bulk/import", 
                     json: batch_data,
                     headers: auth_headers)
      
      results << transform_bulk_response(response)
    end
    
    {
      success: true,
      total_records: records.size,
      batch_count: results.size,
      batch_results: results
    }
  end
  
  # Authentication and validation helpers
  
  def auth_headers
    headers = { "X-API-Key" => api_key }
    
    # Add request tracking
    headers["X-Request-ID"] = SecureRandom.uuid
    headers["X-Timestamp"] = Time.now.to_i.to_s
    
    headers
  end
  
  def validate_api_key!
    raise ArgumentError, "CRM API key not configured" unless api_key
  end
  
  def validate_email!(email)
    unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      raise ArgumentError, "Invalid email format: #{email}"
    end
  end
  
  def validate_id!(id)
    unless id.to_s.match?(/\A\d+\z/)
      raise ArgumentError, "Invalid ID format: #{id}"
    end
  end
  
  # Response transformation methods
  
  def transform_contact_response(response)
    return response if response[:error]
    
    {
      type: "contact",
      id: response["id"],
      name: response["name"],
      email: response["email"],
      company: response["company"],
      phone: response["phone"],
      created_at: response["created_at"],
      updated_at: response["updated_at"],
      custom_fields: response["custom_fields"] || {},
      source: "crm_api"
    }
  end
  
  def transform_company_response(response)
    return response if response[:error]
    
    {
      type: "company",
      id: response["id"],
      name: response["name"],
      industry: response["industry"],
      size: response["size"],
      website: response["website"],
      created_at: response["created_at"],
      custom_fields: response["custom_fields"] || {},
      source: "crm_api"
    }
  end
  
  def transform_deal_response(response)
    return response if response[:error]
    
    {
      type: "deal",
      id: response["id"],
      title: response["title"],
      value: response["value"],
      stage: response["stage"],
      contact_id: response["contact_id"],
      company_id: response["company_id"],
      created_at: response["created_at"],
      custom_fields: response["custom_fields"] || {},
      source: "crm_api"
    }
  end
  
  def transform_search_response(response, data_type)
    return response if response[:error]
    
    {
      type: "search_results",
      data_type: data_type,
      query: response["query"],
      total_count: response["total"] || response["count"] || 0,
      page_size: response["limit"] || 25,
      page_offset: response["offset"] || 0,
      results: response["results"] || response["data"] || [],
      has_more: (response["total"] || 0) > (response["offset"] || 0) + (response["limit"] || 25),
      search_time: response["search_time"],
      source: "crm_api"
    }
  end
  
  def transform_analytics_response(response)
    return response if response[:error]
    
    {
      type: "analytics",
      report_type: response["report_type"],
      date_range: response["date_range"],
      generated_at: response["generated_at"] || Time.now.iso8601,
      data: response["data"] || {},
      summary: response["summary"] || {},
      source: "crm_api"
    }
  end
  
  def transform_bulk_response(response)
    return response if response[:error]
    
    {
      batch_id: response["batch_id"],
      processed_count: response["processed"] || 0,
      success_count: response["success_count"] || 0,
      error_count: response["error_count"] || 0,
      errors: response["errors"] || [],
      processing_time: response["processing_time"]
    }
  end
  
  # Error handling
  
  def handle_error(error, action, params)
    error_response = {
      error: "CRM tool error",
      action: action,
      error_type: error.class.name,
      message: error.message,
      timestamp: Time.now.iso8601
    }
    
    # Add context for debugging (but not sensitive data)
    error_response[:context] = {
      action: action,
      param_keys: params.keys,
      api_configured: !api_key.nil?
    }
    
    # Log error for monitoring
    log_error(error, action, params)
    
    error_response
  end
  
  def log_error(error, action, params)
    # In a real implementation, you might use a logging service
    puts "[CRM Tool Error] #{error.class.name}: #{error.message}"
    puts "  Action: #{action}"
    puts "  Params: #{params.keys.join(', ')}"
  end
  
  # Helper methods
  
  def available_actions
    %w[
      create_contact update_contact search_contacts delete_contact
      create_company search_companies
      create_deal
      get_analytics
      bulk_import
    ]
  end
end

# Demonstration of the complex API tool
if __FILE__ == $0
  puts "=== Complex API Tool Example ==="
  puts
  
  # Create an instance
  crm_tool = CRMTool.new
  
  # Show tool metadata
  puts "Tool Information:"
  puts "  Name: #{crm_tool.name}"
  puts "  Description: #{crm_tool.description}"
  puts "  Endpoint: #{crm_tool.class.endpoint_url}"
  puts "  Timeout: #{crm_tool.class.timeout_value || 30}s"
  puts "  API Key Configured: #{!crm_tool.api_key.nil?}"
  puts
  
  # Show auto-generated parameter schema
  definition = crm_tool.to_tool_definition
  puts "Auto-Generated Parameter Schema:"
  params = definition[:function][:parameters][:properties]
  params.each do |param, schema|
    puts "  #{param}: #{schema[:type]} - #{schema[:description]}"
  end
  puts
  
  # Demonstrate action-based calls (with simulated responses)
  puts "=== Tool Usage Examples ==="
  puts
  
  # Example 1: Create Contact
  puts "1. Creating a contact:"
  begin
    result = crm_tool.call(
      action: "create_contact",
      name: "John Doe",
      email: "john.doe@example.com",
      company: "Acme Corp",
      phone: "+1-555-0123",
      role: "Developer"
    )
    puts "   Result: #{result}"
  rescue => e
    puts "   Expected error (API not configured): #{e.message}"
  end
  
  puts
  
  # Example 2: Search with filters
  puts "2. Searching contacts:"
  begin
    result = crm_tool.call(
      action: "search_contacts",
      query: "john",
      limit: 10,
      filters: { company: "Acme Corp" },
      sort_by: "name"
    )
    puts "   Result: #{result}"
  rescue => e
    puts "   Expected error (API not configured): #{e.message}"
  end
  
  puts
  
  # Example 3: Bulk import
  puts "3. Bulk import example:"
  contacts = [
    { name: "Alice Smith", email: "alice@example.com" },
    { name: "Bob Johnson", email: "bob@example.com" }
  ]
  
  begin
    result = crm_tool.call(
      action: "bulk_import",
      data_type: "contacts",
      records: contacts,
      batch_size: 2
    )
    puts "   Result: #{result}"
  rescue => e
    puts "   Expected error (API not configured): #{e.message}"
  end
  
  puts
  
  # Example 4: Error handling
  puts "4. Error handling - invalid action:"
  result = crm_tool.call(action: "invalid_action")
  puts "   Result: #{result}"
  
  puts
  
  # Example 5: Validation errors
  puts "5. Validation error - invalid email:"
  begin
    result = crm_tool.call(
      action: "create_contact",
      name: "Test User",
      email: "invalid-email"
    )
    puts "   Result: #{result}"
  rescue => e
    puts "   Validation error: #{e.message}"
  end
  
  puts
  
  # Show configuration details
  puts "=== Tool Configuration ==="
  config = crm_tool.tool_configuration
  puts "Tool Definition Type: #{config[:tool][:type]}"
  puts "Callable: #{config[:callable].class}"
  puts "Enabled: #{config[:enabled]}"
  puts "Metadata:"
  config[:metadata].each do |key, value|
    puts "  #{key}: #{value}"
  end
  
  puts
  
  # Show available actions
  puts "=== Available Actions ==="
  available_actions = %w[
    create_contact update_contact search_contacts delete_contact
    create_company search_companies
    create_deal
    get_analytics
    bulk_import
  ]
  
  available_actions.each_with_index do |action, i|
    puts "  #{i + 1}. #{action}"
  end
  
  puts
  puts "Complex API tool example completed!"
  puts
  puts "Note: This example demonstrates advanced API tool patterns including:"
  puts "- Action-based routing"
  puts "- Multiple HTTP methods (GET, POST, PUT, DELETE)"
  puts "- Authentication handling"
  puts "- Input validation"
  puts "- Response transformation"
  puts "- Error handling and recovery"
  puts "- Bulk operations"
  puts "- Configuration management"
end