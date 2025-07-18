# Rails Examples

This directory contains examples demonstrating Rails integration for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  

## Rails Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `rails_integration_example.rb` | ✅ | Rails application integration | Fully working |

## Running Examples

### Prerequisites

1. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. Install required gems:
   ```bash
   bundle install
   ```

3. Rails application setup:
   ```bash
   rails new my_app
   cd my_app
   # Add RAAF to Gemfile
   ```

### Running Rails Examples

```bash
# Rails integration
ruby rails/examples/rails_integration_example.rb

# In a Rails application
rails server
```

## Rails Integration Features

### Automatic Integration
- **Engine mounting**: RAAF engine mounts automatically
- **Initializer setup**: Configuration loaded from Rails config
- **Middleware integration**: Request/response processing
- **Database integration**: ActiveRecord models for persistence

### Configuration
- **Environment-based**: Different settings per environment
- **Credential management**: Secure API key storage
- **Logging integration**: Uses Rails.logger automatically
- **Asset pipeline**: JavaScript and CSS assets included

### Controller Integration
- **Base controller**: RAAF::Rails::ApplicationController
- **Authentication**: Integrate with existing auth systems
- **Error handling**: Rails-style error handling
- **Response formats**: JSON, HTML, and streaming responses

## Rails Patterns

### Controller Integration
```ruby
class AgentController < ApplicationController
  include RAAF::Rails::AgentHelper
  
  def create
    @agent = create_agent(agent_params)
    respond_to do |format|
      format.json { render json: @agent }
      format.html { redirect_to @agent }
    end
  end
  
  def chat
    response = @agent.run(params[:message])
    render json: { response: response.content }
  end
  
  private
  
  def agent_params
    params.require(:agent).permit(:name, :instructions, :model)
  end
end
```

### Model Integration
```ruby
class Agent < ApplicationRecord
  include RAAF::Rails::AgentModel
  
  belongs_to :user
  has_many :conversations, dependent: :destroy
  
  validates :name, presence: true
  validates :instructions, presence: true
  
  def to_raaf_agent
    RAAF::Agent.new(
      name: name,
      instructions: instructions,
      model: model || 'gpt-4o'
    )
  end
end
```

### View Helpers
```ruby
# In views
<%= agent_chat_widget(@agent) %>
<%= streaming_chat_interface(@agent) %>
<%= agent_configuration_form(@agent) %>
```

## Configuration

### Rails Initializer
```ruby
# config/initializers/raaf.rb
RAAF.configure do |config|
  config.api_key = Rails.application.credentials.openai_api_key
  config.default_model = 'gpt-4o'
  config.enable_tracing = Rails.env.production?
  config.log_level = Rails.env.development? ? :debug : :info
end
```

### Environment Configuration
```yaml
# config/database.yml style configuration
development:
  api_key: <%= Rails.application.credentials.openai_api_key %>
  model: gpt-4o
  enable_tracing: false
  
production:
  api_key: <%= ENV['OPENAI_API_KEY'] %>
  model: gpt-4o
  enable_tracing: true
```

### Routes
```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Rails::Engine => '/agents'
  
  resources :agents do
    member do
      post :chat
      get :stream
    end
  end
end
```

## Database Models

### Migrations
```ruby
class CreateAgents < ActiveRecord::Migration[7.0]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.text :instructions
      t.string :model, default: 'gpt-4o'
      t.references :user, null: false, foreign_key: true
      t.json :configuration
      t.timestamps
    end
  end
end

class CreateConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :conversations do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.json :messages
      t.json :metadata
      t.timestamps
    end
  end
end
```

### Model Relationships
```ruby
class User < ApplicationRecord
  has_many :agents, dependent: :destroy
  has_many :conversations, dependent: :destroy
end

class Agent < ApplicationRecord
  belongs_to :user
  has_many :conversations, dependent: :destroy
  
  scope :active, -> { where(active: true) }
  scope :by_model, ->(model) { where(model: model) }
end

class Conversation < ApplicationRecord
  belongs_to :agent
  belongs_to :user
  
  validates :messages, presence: true
end
```

## Frontend Integration

### JavaScript Integration
```javascript
// app/assets/javascripts/raaf.js
class RAFAgent {
  constructor(agentId) {
    this.agentId = agentId;
  }
  
  async chat(message) {
    const response = await fetch(`/agents/${this.agentId}/chat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ message: message })
    });
    return response.json();
  }
  
  stream(message, callback) {
    const eventSource = new EventSource(`/agents/${this.agentId}/stream?message=${encodeURIComponent(message)}`);
    eventSource.onmessage = (event) => {
      callback(JSON.parse(event.data));
    };
    return eventSource;
  }
}
```

### CSS Styling
```scss
// app/assets/stylesheets/raaf.scss
.agent-chat {
  .message {
    padding: 10px;
    margin: 5px 0;
    border-radius: 8px;
    
    &.user {
      background-color: #e3f2fd;
      text-align: right;
    }
    
    &.assistant {
      background-color: #f5f5f5;
    }
  }
  
  .streaming {
    opacity: 0.7;
    animation: pulse 1s infinite;
  }
}
```

## Testing

### RSpec Integration
```ruby
# spec/rails_helper.rb
require 'raaf/rails/test_helpers'

RSpec.configure do |config|
  config.include RAAF::Rails::TestHelpers
end

# spec/controllers/agent_controller_spec.rb
RSpec.describe AgentController, type: :controller do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  
  before { sign_in user }
  
  describe 'POST #chat' do
    it 'responds with agent message' do
      post :chat, params: { id: agent.id, message: 'Hello' }
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['response']).to be_present
    end
  end
end
```

## Deployment

### Heroku
```yaml
# Procfile
web: bundle exec rails server -p $PORT
worker: bundle exec sidekiq
```

### Docker
```dockerfile
# Dockerfile
FROM ruby:3.2
WORKDIR /app
COPY Gemfile* ./
RUN bundle install
COPY . .
CMD ["rails", "server", "-b", "0.0.0.0"]
```

## Notes

- Rails integration is seamless and follows Rails conventions
- Database models provide persistence for agents and conversations
- Frontend integration supports both synchronous and streaming modes
- Testing helpers make it easy to test agent functionality
- Deployment follows standard Rails deployment practices
- Check individual example files for detailed implementation patterns