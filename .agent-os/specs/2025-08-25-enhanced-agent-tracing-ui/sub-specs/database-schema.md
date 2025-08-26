# Database Schema

This is the database schema implementation for the spec detailed in @.agent-os/specs/2025-08-25-enhanced-agent-tracing-ui/spec.md

> Created: 2025-08-25
> Version: 1.0.0

## Schema Changes

### New Columns for raaf_tracing_spans

Adding enhanced data capture fields to the existing spans table:

```sql
-- Add new JSONB columns for enhanced data capture
ALTER TABLE raaf_tracing_spans 
ADD COLUMN agent_name VARCHAR(255),
ADD COLUMN prompt_data JSONB,
ADD COLUMN input_context JSONB,
ADD COLUMN output_context JSONB, 
ADD COLUMN chat_messages JSONB,
ADD COLUMN execution_metadata JSONB;

-- Add indexes for performance
CREATE INDEX idx_raaf_tracing_spans_agent_name ON raaf_tracing_spans (agent_name);
CREATE INDEX idx_raaf_tracing_spans_execution_time ON raaf_tracing_spans ((execution_metadata->>'start_time'));
CREATE INDEX idx_raaf_tracing_spans_input_context ON raaf_tracing_spans USING gin (input_context);
CREATE INDEX idx_raaf_tracing_spans_output_context ON raaf_tracing_spans USING gin (output_context);
CREATE INDEX idx_raaf_tracing_spans_chat_messages ON raaf_tracing_spans USING gin (chat_messages);
```

### Rails Migration Implementation

```ruby
# db/migrate/add_enhanced_fields_to_spans.rb
class AddEnhancedFieldsToSpans < ActiveRecord::Migration[7.0]
  def up
    add_column :raaf_tracing_spans, :agent_name, :string, limit: 255
    add_column :raaf_tracing_spans, :prompt_data, :jsonb, default: {}
    add_column :raaf_tracing_spans, :input_context, :jsonb, default: {}
    add_column :raaf_tracing_spans, :output_context, :jsonb, default: {}
    add_column :raaf_tracing_spans, :chat_messages, :jsonb, default: []
    add_column :raaf_tracing_spans, :execution_metadata, :jsonb, default: {}
    
    # Add performance indexes
    add_index :raaf_tracing_spans, :agent_name
    add_index :raaf_tracing_spans, "(execution_metadata->>'start_time')", 
              name: 'idx_raaf_tracing_spans_execution_time'
    add_index :raaf_tracing_spans, :input_context, using: :gin
    add_index :raaf_tracing_spans, :output_context, using: :gin  
    add_index :raaf_tracing_spans, :chat_messages, using: :gin
  end
  
  def down
    remove_index :raaf_tracing_spans, :agent_name
    remove_index :raaf_tracing_spans, name: 'idx_raaf_tracing_spans_execution_time'
    remove_index :raaf_tracing_spans, :input_context
    remove_index :raaf_tracing_spans, :output_context
    remove_index :raaf_tracing_spans, :chat_messages
    
    remove_column :raaf_tracing_spans, :agent_name
    remove_column :raaf_tracing_spans, :prompt_data
    remove_column :raaf_tracing_spans, :input_context
    remove_column :raaf_tracing_spans, :output_context
    remove_column :raaf_tracing_spans, :chat_messages
    remove_column :raaf_tracing_spans, :execution_metadata
  end
end
```

## Data Structure Specifications

### agent_name Column
- **Type**: VARCHAR(255)
- **Purpose**: Store the name of the agent that executed this span
- **Example**: "CustomerSupportAgent", "DataAnalyzer", "ReportGenerator"
- **Constraints**: NOT NULL when span represents an agent execution

### prompt_data JSONB Column
```json
{
  "text": "Analyze the customer data for insights about purchasing behavior",
  "template": "Analyze the #{data_type} data for insights about #{focus_area}",
  "variables": {
    "data_type": "customer",
    "focus_area": "purchasing behavior"
  },
  "model": "gpt-4o",
  "temperature": 0.7,
  "max_tokens": 1000
}
```

### input_context JSONB Column
```json
{
  "data": {
    "customer_records": [...],
    "date_range": "2024-01-01 to 2024-12-31",
    "analysis_type": "behavioral"
  },
  "schema": {
    "customer_records": "array",
    "date_range": "string",
    "analysis_type": "enum[behavioral,demographic,geographic]"
  },
  "validation_results": [
    {
      "field": "customer_records",
      "status": "valid",
      "message": "1,250 records found"
    }
  ]
}
```

### output_context JSONB Column
```json
{
  "data": {
    "insights": [...],
    "recommendations": [...],
    "confidence_score": 0.87
  },
  "schema": {
    "insights": "array",
    "recommendations": "array", 
    "confidence_score": "float[0.0-1.0]"
  },
  "transformations": [
    {
      "step": "data_analysis",
      "duration_ms": 1250,
      "records_processed": 1250
    },
    {
      "step": "insight_generation", 
      "duration_ms": 800,
      "insights_generated": 12
    }
  ]
}
```

### chat_messages JSONB Column
```json
[
  {
    "role": "system",
    "content": "You are a helpful data analyst...",
    "timestamp": "2024-01-15T10:30:00.000Z"
  },
  {
    "role": "user", 
    "content": "Analyze this customer data for purchasing patterns",
    "timestamp": "2024-01-15T10:30:05.123Z"
  },
  {
    "role": "assistant",
    "content": "I'll analyze the customer data and provide insights...",
    "timestamp": "2024-01-15T10:30:07.456Z"
  }
]
```

### execution_metadata JSONB Column
```json
{
  "agent_class": "CustomerAnalysisAgent",
  "agent_version": "1.2.0",
  "start_time": "2024-01-15T10:30:00.000Z",
  "end_time": "2024-01-15T10:32:15.789Z",
  "duration_ms": 135789,
  "memory_usage_mb": 45.2,
  "cpu_time_ms": 12500,
  "tools_used": ["data_analyzer", "report_generator"],
  "handoffs": [
    {
      "from_agent": "CustomerAnalysisAgent",
      "to_agent": "ReportGenerator", 
      "timestamp": "2024-01-15T10:31:30.000Z"
    }
  ],
  "error_info": null,
  "retry_count": 0
}
```

## Constraints and Validation

### Database-Level Constraints
```sql
-- Ensure agent_name is present for agent spans
ALTER TABLE raaf_tracing_spans 
ADD CONSTRAINT check_agent_name_for_agent_spans 
CHECK (
  (kind != 'agent') OR 
  (kind = 'agent' AND agent_name IS NOT NULL AND length(agent_name) > 0)
);

-- Ensure JSONB fields are valid JSON
ALTER TABLE raaf_tracing_spans 
ADD CONSTRAINT check_valid_prompt_data 
CHECK (prompt_data IS NULL OR jsonb_typeof(prompt_data) = 'object');

ALTER TABLE raaf_tracing_spans
ADD CONSTRAINT check_valid_chat_messages
CHECK (chat_messages IS NULL OR jsonb_typeof(chat_messages) = 'array');
```

### ActiveRecord Model Validations
```ruby
class RAAF::Tracing::SpanRecord < ActiveRecord::Base
  validates :agent_name, presence: true, if: -> { kind == 'agent' }
  validates :agent_name, length: { maximum: 255 }
  
  validate :validate_jsonb_structure
  
  private
  
  def validate_jsonb_structure
    validate_prompt_data_structure if prompt_data.present?
    validate_chat_messages_structure if chat_messages.present?
    validate_context_structure(:input_context) if input_context.present?
    validate_context_structure(:output_context) if output_context.present?
  end
  
  def validate_prompt_data_structure
    required_keys = %w[text]
    optional_keys = %w[template variables model temperature max_tokens]
    validate_json_keys(:prompt_data, required_keys, optional_keys)
  end
  
  def validate_chat_messages_structure
    unless chat_messages.is_a?(Array)
      errors.add(:chat_messages, 'must be an array')
      return
    end
    
    chat_messages.each_with_index do |message, index|
      unless message.is_a?(Hash) && message.key?('role') && message.key?('content')
        errors.add(:chat_messages, "message at index #{index} must have 'role' and 'content'")
      end
    end
  end
  
  def validate_context_structure(field)
    context_data = send(field)
    required_keys = %w[data]
    optional_keys = %w[schema validation_results transformations]
    validate_json_keys(field, required_keys, optional_keys)
  end
end
```

## Performance Optimizations

### Partial Indexes for Common Queries
```sql
-- Index only spans with agent names (most common query pattern)
CREATE INDEX idx_raaf_tracing_spans_agent_name_partial 
ON raaf_tracing_spans (agent_name) 
WHERE agent_name IS NOT NULL;

-- Index only recent spans for dashboard queries
CREATE INDEX idx_raaf_tracing_spans_recent
ON raaf_tracing_spans (start_time DESC)
WHERE start_time > (CURRENT_TIMESTAMP - INTERVAL '30 days');

-- Composite index for filtered searches
CREATE INDEX idx_raaf_tracing_spans_agent_time
ON raaf_tracing_spans (agent_name, start_time DESC)
WHERE agent_name IS NOT NULL;
```

### JSONB Query Optimization Examples
```sql
-- Efficient queries using JSONB operators
SELECT * FROM raaf_tracing_spans 
WHERE input_context @> '{"data": {"analysis_type": "behavioral"}}';

SELECT * FROM raaf_tracing_spans 
WHERE execution_metadata->>'agent_class' = 'CustomerAnalysisAgent';

SELECT * FROM raaf_tracing_spans 
WHERE jsonb_array_length(chat_messages) > 5;
```

## Data Retention and Cleanup

### Automated Cleanup Job
```ruby
# Cleanup job for old enhanced tracing data
class RAAF::Tracing::EnhancedDataCleanupJob < ApplicationJob
  def perform(retention_days: 90)
    cutoff_date = retention_days.days.ago
    
    # Clean up old spans with enhanced data
    deleted_count = RAAF::Tracing::SpanRecord
      .where('start_time < ?', cutoff_date)
      .where.not(agent_name: nil)
      .delete_all
      
    Rails.logger.info "Cleaned up #{deleted_count} old enhanced tracing records"
  end
end
```

## Migration Rollback Strategy

### Safe Migration Rollback
```ruby
# Safe rollback that preserves existing data
def safe_rollback
  # Step 1: Remove indexes (fast)
  remove_index :raaf_tracing_spans, :agent_name if index_exists?(:raaf_tracing_spans, :agent_name)
  
  # Step 2: Drop columns (potentially slow - consider background migration)
  remove_column :raaf_tracing_spans, :agent_name
  remove_column :raaf_tracing_spans, :prompt_data
  remove_column :raaf_tracing_spans, :input_context
  remove_column :raaf_tracing_spans, :output_context
  remove_column :raaf_tracing_spans, :chat_messages
  remove_column :raaf_tracing_spans, :execution_metadata
end
```

### Data Migration Strategy
For existing installations, provide data migration utilities to populate new fields from existing span attributes where possible.