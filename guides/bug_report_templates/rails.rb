# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "rails"
  gem "raaf"
  gem "rspec"
  gem "sqlite3"
  # If you want to test against edge RAAF replace the raaf line with this:
  # gem "raaf", github: "enterprisemodules/raaf", branch: "main"
end

require "rails"
require "raaf"
require "rspec/autorun"

# Minimal Rails app for testing
class TestApp < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.logger = Logger.new(IO::NULL)
  config.active_support.deprecation = :stderr
  
  # Database configuration
  config.active_record.database_url = "sqlite3::memory:"
end

Rails.application.initialize!

# Create test models
ActiveRecord::Schema.define do
  create_table :agent_memories do |t|
    t.string :session_id, null: false
    t.string :role, null: false
    t.text :content, null: false
    t.json :metadata
    t.timestamps
  end
  
  add_index :agent_memories, :session_id
end

class AgentMemory < ActiveRecord::Base
  validates :session_id, :role, :content, presence: true
  validates :role, inclusion: { in: %w[user assistant system tool] }
  
  scope :for_session, ->(session_id) { where(session_id: session_id) }
end

RSpec.describe "RAAF Rails Bug Report" do
  before do
    AgentMemory.delete_all
  end

  it "integrates RAAF memory with ActiveRecord" do
    memory_store = RAAF::Rails::ActiveRecordMemoryStore.new(
      model_class: AgentMemory
    )
    
    memory_manager = RAAF::Memory::MemoryManager.new(
      store: memory_store
    )
    
    session_id = "rails_test_session"
    
    # Add message through RAAF
    memory_manager.add_message(
      session_id: session_id,
      role: "user",
      content: "Hello from Rails!"
    )
    
    # Verify it was stored in ActiveRecord
    stored_memory = AgentMemory.for_session(session_id).first
    expect(stored_memory.role).to eq("user")
    expect(stored_memory.content).to eq("Hello from Rails!")
  end

  it "mounts RAAF Rails engine correctly" do
    # Test that RAAF Rails engine can be mounted
    routes = Rails.application.routes_reloader.reload!
    
    # Mount the engine
    Rails.application.routes.draw do
      mount RAAF::Rails::Engine => "/raaf", as: "raaf"
    end
    
    # Verify route exists
    expect(Rails.application.routes.url_helpers).to respond_to(:raaf_path)
  end

  it "configures RAAF settings in Rails" do
    # Test Rails-specific RAAF configuration
    Rails.application.configure do
      config.raaf = ActiveSupport::OrderedOptions.new
      config.raaf.default_model = "gpt-4o-mini"
      config.raaf.tracing_enabled = true
      config.raaf.dashboard_enabled = true
    end
    
    expect(Rails.application.config.raaf.default_model).to eq("gpt-4o-mini")
    expect(Rails.application.config.raaf.tracing_enabled).to be true
    expect(Rails.application.config.raaf.dashboard_enabled).to be true
  end

  it "integrates RAAF with Rails controllers" do
    # Test RAAF integration in Rails controllers
    class TestController < ActionController::Base
      def chat
        agent = RAAF::Agent.new(
          name: "RailsAgent",
          instructions: "You are integrated with Rails",
          model: "gpt-4o-mini"
        )
        
        runner = RAAF::Runner.new(agent: agent)
        
        # This would normally process the request
        render json: { status: "success", agent_name: agent.name }
      end
    end
    
    controller = TestController.new
    expect(controller).to respond_to(:chat)
  end

  it "processes RAAF agents in background jobs" do
    # Test RAAF integration with ActiveJob
    class AgentProcessingJob < ActiveJob::Base
      def perform(message, agent_config)
        agent = RAAF::Agent.new(**agent_config)
        runner = RAAF::Runner.new(agent: agent)
        
        # Process message in background
        result = { message: message, agent: agent.name }
        result
      end
    end
    
    job = AgentProcessingJob.new
    result = job.perform(
      "Test message",
      {
        name: "BackgroundAgent",
        instructions: "Process in background",
        model: "gpt-4o-mini"
      }
    )
    
    expect(result[:message]).to eq("Test message")
    expect(result[:agent]).to eq("BackgroundAgent")
  end

  it "integrates RAAF with Rails middleware" do
    # Test RAAF middleware integration
    class RAFMiddleware
      def initialize(app)
        @app = app
      end
      
      def call(env)
        # Add RAAF context to request
        env['raaf.context'] = {
          user_id: env['HTTP_USER_ID'],
          session_id: env['HTTP_SESSION_ID']
        }
        
        @app.call(env)
      end
    end
    
    middleware = RAFMiddleware.new(->(env) { [200, {}, ['OK']] })
    
    response = middleware.call({
      'HTTP_USER_ID' => '123',
      'HTTP_SESSION_ID' => 'abc'
    })
    
    expect(response[0]).to eq(200)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific Rails bug case" do
    # Replace this with your specific test case that demonstrates the Rails integration bug
    expect(true).to be true # Replace this with your actual test case
  end
end