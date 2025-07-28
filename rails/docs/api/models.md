# Models API

## Overview

RAAF Rails provides ActiveRecord models for persisting and managing AI agents, conversations, and messages. These models integrate seamlessly with your Rails application and provide a rich API for agent management.

## AgentModel

The `RAAF::Rails::AgentModel` represents an AI agent configuration.

### Schema

```ruby
create_table :raaf_agents do |t|
  t.string :name, null: false
  t.text :instructions, null: false
  t.string :model, null: false
  t.string :status, default: "draft"
  t.references :user, foreign_key: true
  t.jsonb :tools, default: []
  t.jsonb :handoffs, default: []
  t.jsonb :metadata, default: {}
  t.jsonb :config, default: {}
  t.timestamps
  
  t.index :name
  t.index :status
  t.index :user_id
end
```

### Class Methods

#### Creation

```ruby
# Basic creation
agent = RAAF::Rails::AgentModel.create!(
  name: "Customer Support",
  instructions: "You are a helpful customer support agent",
  model: "gpt-4o",
  user: current_user
)

# With tools and metadata
agent = RAAF::Rails::AgentModel.create!(
  name: "Sales Assistant",
  instructions: "Help customers find the right products",
  model: "gpt-4o",
  user: current_user,
  tools: ["product_search", "inventory_check"],
  metadata: {
    department: "sales",
    region: "north",
    languages: ["en", "es"]
  }
)
```

#### Scopes

```ruby
# Status scopes
RAAF::Rails::AgentModel.draft      # status = 'draft'
RAAF::Rails::AgentModel.deployed   # status = 'deployed'
RAAF::Rails::AgentModel.active     # deployed AND updated recently

# User scopes
RAAF::Rails::AgentModel.by_user(user)        # user_id = user.id
RAAF::Rails::AgentModel.by_user_id(user_id)  # user_id = user_id

# Tool scopes
RAAF::Rails::AgentModel.with_tool("search")  # tools contains 'search'
RAAF::Rails::AgentModel.with_any_tool(["search", "calc"])  # has any tool

# Search
RAAF::Rails::AgentModel.search("customer")   # name or instructions match
```

### Instance Methods

#### Status Management

```ruby
# Deployment
agent.deploy!     # Changes status to 'deployed'
agent.undeploy!   # Changes status to 'draft'
agent.deployed?   # Returns true if deployed
agent.draft?      # Returns true if draft

# Validation before deployment
agent.can_deploy? # Checks if agent is ready for deployment
agent.deployment_errors # Returns array of errors preventing deployment
```

#### Message Processing

```ruby
# Process a single message
result = agent.process_message("Hello!", context: { user: current_user })
# Returns:
# {
#   content: "Hello! How can I help you today?",
#   usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 },
#   metadata: { model: "gpt-4o", response_time: 1.2 }
# }

# Process with streaming
agent.process_message("Tell me a story") do |chunk|
  print chunk[:content]
end
```

#### Tool Management

```ruby
# Add tools
agent.add_tool("web_search")
agent.add_tool(MyCustomTool.new)

# Remove tools
agent.remove_tool("web_search")

# Check tools
agent.has_tool?("web_search")  # => true
agent.tools                     # => ["web_search", "calculator"]

# Tool instances
agent.tool_instances            # Returns instantiated tool objects
```

#### Handoff Management

```ruby
# Add handoff targets
agent.add_handoff(support_agent)
agent.add_handoff("SalesAgent")  # By name

# Remove handoffs
agent.remove_handoff("SalesAgent")

# Check handoffs
agent.can_handoff_to?(sales_agent)  # => true
agent.handoff_targets                # => [support_agent, sales_agent]
```

#### Statistics

```ruby
# Conversation metrics
agent.conversation_count      # Total conversations
agent.active_conversations    # Currently active
agent.message_count          # Total messages

# Usage metrics
agent.total_tokens_used      # Total tokens consumed
agent.total_cost            # Estimated cost
agent.average_tokens_per_message

# Performance metrics
agent.average_response_time  # In seconds
agent.success_rate          # Percentage
agent.error_rate            # Percentage
```

### Callbacks

```ruby
class MyAgentModel < RAAF::Rails::AgentModel
  # Lifecycle callbacks
  before_create :set_defaults
  after_create :notify_admin
  before_deploy :validate_configuration
  after_deploy :start_monitoring
  
  private
  
  def set_defaults
    self.config[:max_tokens] ||= 1000
  end
  
  def validate_configuration
    errors.add(:base, "Tools required") if tools.empty?
    throw(:abort) if errors.any?
  end
end
```

## ConversationModel

The `RAAF::Rails::ConversationModel` represents a conversation session.

### Schema

```ruby
create_table :raaf_conversations do |t|
  t.references :agent, null: false, foreign_key: { to_table: :raaf_agents }
  t.references :user, foreign_key: true
  t.string :status, default: "active"
  t.jsonb :context, default: {}
  t.jsonb :metadata, default: {}
  t.datetime :completed_at
  t.timestamps
  
  t.index :status
  t.index :created_at
end
```

### Class Methods

```ruby
# Creation
conversation = RAAF::Rails::ConversationModel.create!(
  agent: agent,
  user: current_user,
  context: {
    session_id: session.id,
    ip_address: request.remote_ip,
    user_agent: request.user_agent
  }
)

# Scopes
RAAF::Rails::ConversationModel.active      # status = 'active'
RAAF::Rails::ConversationModel.completed   # status = 'completed'
RAAF::Rails::ConversationModel.abandoned   # No messages in 30 mins
RAAF::Rails::ConversationModel.recent(1.day)
RAAF::Rails::ConversationModel.by_agent(agent)
RAAF::Rails::ConversationModel.by_user(user)
```

### Instance Methods

```ruby
# Message management
conversation.add_message("Hello", role: "user")
conversation.add_user_message("How are you?")
conversation.add_assistant_message("I'm doing well!", usage: {})

# Status management
conversation.complete!
conversation.abandon!
conversation.reactivate!

# Queries
conversation.messages           # All messages
conversation.user_messages     # User messages only
conversation.assistant_messages # Assistant messages only
conversation.last_message      # Most recent message
conversation.last_user_message
conversation.last_assistant_message

# Metrics
conversation.duration          # In seconds
conversation.message_count
conversation.total_tokens
conversation.total_cost
conversation.average_response_time
```

## MessageModel

The `RAAF::Rails::MessageModel` represents individual messages.

### Schema

```ruby
create_table :raaf_messages do |t|
  t.references :conversation, null: false, foreign_key: { to_table: :raaf_conversations }
  t.text :content, null: false
  t.string :role, null: false
  t.jsonb :usage, default: {}
  t.jsonb :metadata, default: {}
  t.jsonb :tool_calls, default: []
  t.datetime :created_at, null: false
  
  t.index :role
  t.index :created_at
end
```

### Class Methods

```ruby
# Creation
message = RAAF::Rails::MessageModel.create!(
  conversation: conversation,
  content: "How can I help you today?",
  role: "assistant",
  usage: {
    input_tokens: 15,
    output_tokens: 20,
    total_tokens: 35
  },
  metadata: {
    model: "gpt-4o",
    response_time: 1.2,
    temperature: 0.7
  }
)

# Scopes
RAAF::Rails::MessageModel.by_role("user")
RAAF::Rails::MessageModel.by_role("assistant")
RAAF::Rails::MessageModel.with_tool_calls
RAAF::Rails::MessageModel.without_tool_calls
RAAF::Rails::MessageModel.recent(1.hour)
RAAF::Rails::MessageModel.with_errors
```

### Instance Methods

```ruby
# Role checks
message.user?       # role == "user"
message.assistant?  # role == "assistant"
message.system?     # role == "system"

# Tool calls
message.has_tool_calls?
message.tool_call_names  # ["web_search", "calculator"]
message.tool_results     # Results from tool executions

# Metrics
message.token_count      # Total tokens
message.response_time    # From metadata
message.cost_estimate    # Based on model and tokens
```

## Associations

```ruby
# Agent associations
agent.conversations
agent.messages           # Through conversations
agent.users             # Through conversations
agent.active_conversations

# Conversation associations
conversation.agent
conversation.user
conversation.messages

# Message associations
message.conversation
message.agent           # Through conversation
message.user            # Through conversation
```

## Validations

```ruby
# AgentModel validations
validates :name, presence: true, uniqueness: { scope: :user_id }
validates :instructions, presence: true, length: { minimum: 10 }
validates :model, presence: true, inclusion: { in: ALLOWED_MODELS }
validates :status, inclusion: { in: %w[draft deployed error] }

# ConversationModel validations
validates :agent, presence: true
validates :status, inclusion: { in: %w[active completed abandoned] }

# MessageModel validations
validates :content, presence: true
validates :role, inclusion: { in: %w[user assistant system] }
validates :usage, presence: true, if: :assistant?
```

## Advanced Queries

```ruby
# Complex queries
agents = RAAF::Rails::AgentModel
  .deployed
  .joins(:conversations)
  .where("raaf_conversations.created_at > ?", 1.week.ago)
  .group("raaf_agents.id")
  .having("COUNT(raaf_conversations.id) > ?", 10)
  .order(conversations_count: :desc)

# With includes
conversations = RAAF::Rails::ConversationModel
  .includes(:agent, :messages)
  .where(user: current_user)
  .recent(24.hours)

# Raw SQL
RAAF::Rails::AgentModel.find_by_sql([
  "SELECT a.*, COUNT(c.id) as conv_count
   FROM raaf_agents a
   LEFT JOIN raaf_conversations c ON c.agent_id = a.id
   WHERE a.user_id = ?
   GROUP BY a.id
   ORDER BY conv_count DESC",
  current_user.id
])
```

## Model Configuration

```ruby
# config/initializers/raaf_models.rb
RAAF::Rails::AgentModel.class_eval do
  # Add custom behavior
  scope :featured, -> { where(featured: true) }
  
  # Override methods
  def deploy!
    # Custom deployment logic
    super
    notify_deployment_service
  end
end
```