# Markdown example validation
ENV["RAAF_TEST_MODE"] = "true"
ENV["OPENAI_API_KEY"] ||= "test-key"

# Add all RAAF gem paths to load path


require_relative "lib/raaf-dsl"

# Stub runner if needed for test mode
if ENV["RAAF_TEST_MODE"] == "true"
  module RAAF
    class Runner
      def run(message)
        Struct.new(:messages).new([
          { role: "user", content: message },
          { role: "assistant", content: "Test response in test mode" }
        ])
      end
    end
  end
end

# Execute the markdown code
class DocumentAnalyzer < RAAF::DSL::Agent

  # Agent identification and configuration
  agent_name "DocumentAnalyzerAgent"
  description "Performs comprehensive document analysis and content extraction"
  
  # Tool integrations
  uses_tool :text_extraction, max_pages: 50
  uses_tool :database_query, timeout: 30
  
  # Response schema with validation
  schema do
    field :insights, type: :array, required: true do
      field :category, type: :string, required: true
      field :finding, type: :string, required: true
      field :confidence, type: :integer, range: 0..100
    end
    field :summary, type: :string, required: true
    field :methodology, type: :string, required: true
  end
  
  # Optional: Execution hooks
end


# Exit cleanly
exit(0)
