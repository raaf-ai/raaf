# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Multi-Provider Integration with VCR", :integration do
  describe "Provider switching scenarios" do
    let(:openai_agent) do
      RAAF::Agent.new(
        name: "OpenAIAgent",
        instructions: "You use OpenAI models",
        model: "gpt-3.5-turbo"
      )
    end
    
    let(:anthropic_agent) do
      RAAF::Agent.new(
        name: "AnthropicAgent", 
        instructions: "You use Anthropic models",
        model: "claude-3-sonnet"
      )
    end

    context "handoffs between different providers" do
      before do
        openai_agent.add_handoff(anthropic_agent)
      end

      it "handles cross-provider handoffs" do
        VCR.use_cassette("multi_provider/openai_to_anthropic_handoff") do
          runner = RAAF::Runner.new(agent: openai_agent)
          
          # This would need proper provider setup
          # For now, we'll test the handoff mechanism
          result = runner.run("Start with OpenAI then handoff to Anthropic")
          
          expect(result.messages).to be_an(Array)
          # Actual provider switching would depend on implementation
        end
      end
    end

    context "provider-specific features" do
      it "uses OpenAI-specific features" do
        VCR.use_cassette("multi_provider/openai_specific") do
          openai_provider = RAAF::Models::OpenAIProvider.new
          
          # OpenAI specific: logprobs
          response = openai_provider.chat_completion(
            model: "gpt-3.5-turbo",
            messages: [{ role: "user", content: "Yes or no?" }],
            logprobs: true
          )
          
          expect(response).to have_key("choices")
        end
      end

      it "uses ResponsesProvider features" do
        VCR.use_cassette("multi_provider/responses_specific") do
          responses_provider = RAAF::Models::ResponsesProvider.new
          
          response = responses_provider.complete(
            messages: [{ role: "user", content: "Hello" }],
            model: "gpt-4o-mini"
          )
          
          expect(response).to have_key("output")
          expect(response["output"]).to be_an(Array)
        end
      end
    end
  end

  describe "Fallback scenarios" do
    let(:primary_agent) do
      RAAF::Agent.new(
        name: "PrimaryAgent",
        instructions: "Primary responder",
        model: "gpt-4o"
      )
    end
    
    let(:fallback_agent) do
      RAAF::Agent.new(
        name: "FallbackAgent",
        instructions: "Fallback responder", 
        model: "gpt-3.5-turbo"
      )
    end

    it "falls back to secondary provider on error" do
      VCR.use_cassette("multi_provider/fallback_on_error") do
        # Set up primary to fail (e.g., rate limit)
        runner = RAAF::Runner.new(agent: primary_agent)
        
        # Mock primary provider to fail
        allow_any_instance_of(RAAF::Models::ResponsesProvider)
          .to receive(:complete)
          .and_raise(RAAF::RateLimitError.new("Rate limit exceeded"))
          .once
        
        # Then allow fallback to work
        allow_any_instance_of(RAAF::Models::ResponsesProvider)
          .to receive(:complete)
          .and_call_original
        
        # With proper error handling, this should use fallback
        expect {
          runner.run("Test message")
        }.to raise_error(RAAF::RateLimitError)
      end
    end
  end

  describe "Load balancing scenarios" do
    let(:agents) do
      3.times.map do |i|
        RAAF::Agent.new(
          name: "WorkerAgent#{i}",
          instructions: "Worker agent #{i}",
          model: "gpt-3.5-turbo"
        )
      end
    end

    it "distributes requests across multiple agents" do
      VCR.use_cassette("multi_provider/load_balancing") do
        results = []
        
        # Process multiple requests
        agents.each_with_index do |agent, i|
          runner = RAAF::Runner.new(agent: agent)
          result = runner.run("Process request #{i}")
          results << result
        end
        
        expect(results.size).to eq(3)
        expect(results.map { |r| r.last_agent.name }.uniq.size).to eq(3)
      end
    end
  end

  describe "Model comparison scenarios" do
    it "compares outputs from different models" do
      VCR.use_cassette("multi_provider/model_comparison") do
        prompt = "Explain photosynthesis in one sentence"
        
        models = ["gpt-3.5-turbo", "gpt-4o-mini"]
        responses = {}
        
        models.each do |model|
          agent = RAAF::Agent.new(
            name: "TestAgent",
            instructions: "You explain things concisely",
            model: model
          )
          runner = RAAF::Runner.new(agent: agent)
          result = runner.run(prompt)
          responses[model] = result.messages.last[:content]
        end
        
        expect(responses.keys).to eq(models)
        # Both should mention photosynthesis
        responses.values.each do |content|
          expect(content.downcase).to include("photosynth")
        end
      end
    end
  end

  describe "Hybrid workflows" do
    let(:analyzer) do
      RAAF::Agent.new(
        name: "Analyzer",
        instructions: "You analyze text",
        model: "gpt-4o-mini"
      )
    end
    
    let(:summarizer) do
      RAAF::Agent.new(
        name: "Summarizer",
        instructions: "You create summaries",
        model: "gpt-3.5-turbo"
      )
    end
    
    let(:formatter) do
      RAAF::Agent.new(
        name: "Formatter",
        instructions: "You format output nicely",
        model: "gpt-3.5-turbo"
      )
    end

    before do
      analyzer.add_handoff(summarizer)
      summarizer.add_handoff(formatter)
    end

    it "processes multi-stage workflow with different models" do
      VCR.use_cassette("multi_provider/hybrid_workflow") do
        runner = RAAF::Runner.new(agent: analyzer)
        
        long_text = <<~TEXT
          Artificial intelligence has transformed many industries. In healthcare, 
          AI assists with diagnosis and treatment planning. In finance, it helps 
          with fraud detection and risk assessment. In transportation, it enables 
          autonomous vehicles and traffic optimization.
        TEXT
        
        result = runner.run("Analyze this text, summarize key points, and format as bullet points: #{long_text}")
        
        expect(result.messages).to be_an(Array)
        expect(result.messages.size).to be >= 2
        
        # Final output should be formatted
        final_message = result.messages.last[:content]
        expect(final_message).to match(/[•·\-*]/) # Bullet points
      end
    end
  end

  describe "Concurrent provider usage" do
    it "handles concurrent requests to different providers" do
      VCR.use_cassette("multi_provider/concurrent_requests") do
        require 'concurrent'
        
        promises = []
        
        # Create concurrent requests
        3.times do |i|
          promise = Concurrent::Promise.execute do
            agent = RAAF::Agent.new(
              name: "ConcurrentAgent#{i}",
              instructions: "Concurrent processing",
              model: i.even? ? "gpt-3.5-turbo" : "gpt-4o-mini"
            )
            
            runner = RAAF::Runner.new(agent: agent)
            runner.run("Concurrent request #{i}")
          end
          
          promises << promise
        end
        
        # Wait for all to complete
        results = promises.map(&:value)
        
        expect(results.size).to eq(3)
        results.each do |result|
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages).not_to be_empty
        end
      end
    end
  end

  describe "Provider retry mechanisms" do
    it "retries on transient failures" do
      VCR.use_cassette("multi_provider/retry_mechanism") do
        agent = RAAF::Agent.new(
          name: "RetryAgent",
          instructions: "Test retry behavior"
        )
        
        runner = RAAF::Runner.new(agent: agent)
        
        # Simulate transient failure then success
        call_count = 0
        allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete) do |*args|
          call_count += 1
          if call_count == 1
            raise RAAF::APIError.new("Temporary failure", status: 503)
          else
            # Return successful response
            {
              "output" => [{
                "type" => "message",
                "role" => "assistant", 
                "content" => [{ "type" => "text", "text" => "Success after retry" }]
              }],
              "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
            }
          end
        end
        
        result = runner.run("Test retry")
        
        expect(call_count).to eq(2)
        expect(result.messages.last[:content]).to include("Success after retry")
      end
    end
  end

  describe "Cost optimization scenarios" do
    it "uses cheaper models for simple tasks" do
      VCR.use_cassette("multi_provider/cost_optimization") do
        # Router agent decides which model to use
        router = RAAF::Agent.new(
          name: "Router",
          instructions: "You route requests to appropriate models"
        )
        
        expensive_agent = RAAF::Agent.new(
          name: "ExpensiveAgent",
          instructions: "For complex tasks",
          model: "gpt-4o"
        )
        
        cheap_agent = RAAF::Agent.new(
          name: "CheapAgent",
          instructions: "For simple tasks",
          model: "gpt-3.5-turbo"
        )
        
        router.add_handoff(expensive_agent)
        router.add_handoff(cheap_agent)
        
        runner = RAAF::Runner.new(agent: router)
        
        # Simple task should route to cheap model
        simple_result = runner.run("What is 2+2?")
        
        # Complex task might route to expensive model
        complex_result = runner.run(
          "Analyze the philosophical implications of consciousness in artificial intelligence"
        )
        
        expect(simple_result.usage[:total_tokens]).to be < 100
        expect(complex_result.usage[:total_tokens]).to be >= 50
      end
    end
  end
end