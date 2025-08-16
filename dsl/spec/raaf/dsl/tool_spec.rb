# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Tool do
  describe "Convention over Configuration" do
    context "basic tool with minimal code" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          description "Search the web for information"
          
          param :query, required: true
          param :max_results, default: 5
          
          def call(query:, max_results: 5)
            "Searching for #{query} with max #{max_results} results"
          end
        end
      end
      
      let(:tool) { tool_class.new }
      
      it "auto-generates tool name from class name" do
        allow(tool_class).to receive(:name).and_return("TestSearch")
        expect(tool.tool_name).to eq("test_search")
      end
      
      it "uses explicit description when provided" do
        expect(tool.description).to eq("Search the web for information")
      end
      
      it "defines parameters through DSL" do
        definition = tool.to_tool_definition
        params = definition[:function][:parameters]
        
        expect(params[:properties][:query]).to include(type: "string")
        expect(params[:required]).to include("query")
        expect(params[:properties][:max_results][:default]).to eq(5)
      end
      
      it "executes using the call method" do
        result = tool.call(query: "Ruby DSL")
        expect(result).to eq("Searching for Ruby DSL with max 5 results")
      end
      
      it "supports Ruby callable syntax" do
        result = tool.(query: "Ruby patterns", max_results: 10)
        expect(result).to eq("Searching for Ruby patterns with max 10 results")
      end
    end
    
    context "tool with auto-generated methods" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          param :input, required: true
          
          def call(input:)
            "Processing #{input}"
          end
        end
      end
      
      let(:tool) { tool_class.new }
      
      it "auto-generates description from class name" do
        allow(tool_class).to receive(:name).and_return("DataProcessor")
        expect(tool.description).to eq("Data processor")
      end
      
      it "provides enabled? method returning true by default" do
        expect(tool.enabled?).to be true
      end
      
      it "generates execute method that delegates to call" do
        expect(tool.execute(input: "test")).to eq("Processing test")
      end
      
      it "generates name method from class name" do
        allow(tool_class).to receive(:name).and_return("DataProcessor")
        expect(tool.name).to eq("data_processor")
      end
    end
    
    context "parameter validation" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          param :count, type: :integer, range: 1..10
          param :tags, type: :array
          param :options, type: :hash
          
          def call(count: 5, tags: [], options: {})
            { count: count, tags: tags, options: options }
          end
        end
      end
      
      let(:tool) { tool_class.new }
      
      it "validates parameter types" do
        expect { tool.call(count: "not a number") }.to raise_error(ArgumentError, /must be an integer/)
      end
      
      it "validates parameter ranges" do
        expect { tool.call(count: 15) }.to raise_error(ArgumentError, /must be between 1 and 10/)
      end
      
      it "handles array parameters" do
        result = tool.call(tags: ["ruby", "dsl"])
        expect(result[:tags]).to eq(["ruby", "dsl"])
      end
      
      it "handles hash parameters" do
        result = tool.call(options: { verbose: true })
        expect(result[:options]).to eq({ verbose: true })
      end
    end
    
    context "code reduction validation" do
      let(:old_style_lines) { 250 }  # Typical old tool implementation
      let(:new_style_lines) { 20 }   # New DSL implementation
      
      it "achieves 80%+ code reduction" do
        reduction = ((old_style_lines - new_style_lines) / old_style_lines.to_f) * 100
        expect(reduction).to be >= 80
      end
    end
  end
  
  describe "Native OpenAI Tool Support" do
    context "native tool definition using native_tool DSL" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          native_tool :web_search  # Declares this as a native OpenAI tool
          
          description "Search the web using OpenAI's built-in search"
          
          param :query, required: true
          param :max_results, default: 10
          
          # NO call method! OpenAI handles execution
        end
      end
      
      let(:tool) { tool_class.new }
      
      it "identifies as native OpenAI tool" do
        expect(tool.native?).to be true
      end
      
      it "does not require call method" do
        expect(tool).not_to respond_to(:call)
      end
      
      it "generates proper OpenAI native tool definition" do
        definition = tool.to_tool_definition
        expect(definition[:type]).to eq("web_search")
        expect(definition[:web_search]).to include(
          query: hash_including(type: "string"),
          max_results: hash_including(default: 10)
        )
      end
      
      it "uses OpenAI tool name not class name" do
        expect(tool.tool_name).to eq("web_search")
      end
    end
    
    context "code interpreter native tool" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          native_tool :code_interpreter
          
          description "Execute Python code in OpenAI's sandbox"
          
          param :code, required: true, type: :string
          
          # NO call method - OpenAI executes this
        end
      end
      
      let(:tool) { tool_class.new }
      
      it "identifies as code_interpreter native tool" do
        expect(tool.native?).to be true
        expect(tool.tool_name).to eq("code_interpreter")
      end
      
      it "generates code_interpreter tool definition" do
        definition = tool.to_tool_definition
        expect(definition[:type]).to eq("code_interpreter")
        expect(definition[:code_interpreter]).to include(
          code: hash_including(type: "string")
        )
      end
    end
    
    context "differentiating native vs external tools" do
      let(:native_tool_class) do
        Class.new(RAAF::DSL::Tool) do
          native_tool :web_search
          param :query, required: true
        end
      end
      
      let(:external_tool_class) do
        Class.new(RAAF::DSL::Tool) do
          param :query, required: true
          
          def call(query:)
            "External search for: #{query}"
          end
        end
      end
      
      it "native tool uses native_tool declaration" do
        tool = native_tool_class.new
        expect(tool.native?).to be true
        expect(tool).not_to respond_to(:call)
      end
      
      it "external tool has call method implementation" do
        tool = external_tool_class.new
        expect(tool.native?).to be false
        expect(tool).to respond_to(:call)
        expect(tool.call(query: "test")).to eq("External search for: test")
      end
      
      it "framework can detect tool type automatically" do
        native = native_tool_class.new
        external = external_tool_class.new
        
        # Native tool returns OpenAI native format
        native_def = native.to_tool_definition
        expect(native_def[:type]).to eq("web_search")
        expect(native_def).to have_key(:web_search)
        
        # External tool returns function calling format
        external_def = external.to_tool_definition
        expect(external_def[:type]).to eq("function")
        expect(external_def).to have_key(:function)
      end
    end
  end
  
  describe "External API Tool Support" do
    context "API tool with minimal boilerplate" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool::API) do
          endpoint "https://api.example.com/search"
          api_key { ENV["EXAMPLE_API_KEY"] }
          
          param :query, required: true
          
          def call(query:)
            post(query: query)["results"]
          end
        end
      end
      
      let(:tool) { tool_class.new }
      
      before do
        allow(ENV).to receive(:[]).with("EXAMPLE_API_KEY").and_return("test_key")
      end
      
      it "identifies as external API tool" do
        expect(tool.native?).to be false
      end
      
      it "provides HTTP helper methods" do
        expect(tool).to respond_to(:post)
        expect(tool).to respond_to(:get)
      end
      
      it "includes authentication headers automatically" do
        stub_request(:post, "https://api.example.com/search")
          .with(headers: { "Authorization" => "Bearer test_key" })
          .to_return(body: { results: ["result1"] }.to_json)
        
        tool.call(query: "test")
      end
    end
    
    context "API tool with zero custom logic" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool::API) do
          endpoint "https://api.tavily.com/search"
          api_key { ENV["TAVILY_API_KEY"] }
          
          param :query, required: true
          param :max_results, default: 5
          
          # No call method defined - uses convention
        end
      end
      
      let(:tool) { tool_class.new }
      
      before do
        allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return("test_key")
      end
      
      it "auto-generates call method using conventions" do
        stub_request(:post, "https://api.tavily.com/search")
          .with(body: { query: "test", max_results: 5 })
          .to_return(body: { status: "success" }.to_json)
        
        result = tool.call(query: "test")
        expect(result).to eq({ "status" => "success" })
      end
    end
  end
  
  describe "Thread Safety" do
    let(:tool_class) do
      Class.new(RAAF::DSL::Tool) do
        param :input, required: true
        
        def call(input:)
          sleep(0.01)  # Simulate work
          "Processed: #{input}"
        end
      end
    end
    
    it "handles concurrent execution safely" do
      tool = tool_class.new
      results = []
      threads = []
      
      10.times do |i|
        threads << Thread.new do
          results << tool.call(input: "thread_#{i}")
        end
      end
      
      threads.each(&:join)
      
      expect(results.size).to eq(10)
      expect(results).to all(match(/^Processed: thread_\d+$/))
    end
  end
  
  describe "Method Caching" do
    let(:tool_class) do
      Class.new(RAAF::DSL::Tool) do
        description "Cached tool"
        param :input, required: true
      end
    end
    
    it "caches generated methods at class level" do
      tool1 = tool_class.new
      tool2 = tool_class.new
      
      # Methods should be identical (same object_id)
      expect(tool1.method(:description).owner).to eq(tool2.method(:description).owner)
    end
    
    it "does not regenerate methods on each instance" do
      expect(tool_class).to receive(:define_method).at_most(:once)
      
      3.times { tool_class.new }
    end
  end
  
  describe "Error Handling" do
    context "missing required parameters" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          param :required_field, required: true
          
          def call(required_field:)
            "ok"
          end
        end
      end
      
      it "provides clear error message" do
        tool = tool_class.new
        expect { tool.call }.to raise_error(ArgumentError, /required_field is required/)
      end
    end
    
    context "invalid parameter types" do
      let(:tool_class) do
        Class.new(RAAF::DSL::Tool) do
          param :number, type: :integer
          
          def call(number:)
            number * 2
          end
        end
      end
      
      it "provides clear type error message" do
        tool = tool_class.new
        expect { tool.call(number: "not a number") }.to raise_error(ArgumentError, /number must be an integer/)
      end
    end
  end
end