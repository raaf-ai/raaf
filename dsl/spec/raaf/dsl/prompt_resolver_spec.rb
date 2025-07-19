# frozen_string_literal: true

require "spec_helper"
require "raaf/prompt_resolver"
require "raaf/prompt_configuration"

RSpec.describe RAAF::PromptResolver do
  let(:test_resolver) do
    Class.new(RAAF::PromptResolver) do
      def can_resolve?(spec)
        spec.is_a?(String) && spec.start_with?("test:")
      end
      
      def resolve(spec, context = {})
        return nil unless can_resolve?(spec)
        
        RAAF::Prompt.new(
          id: spec.delete_prefix("test:"),
          variables: context
        )
      end
    end
  end
  
  describe "#initialize" do
    it "stores name and options" do
      resolver = test_resolver.new(name: :test, priority: 100)
      expect(resolver.name).to eq(:test)
      expect(resolver.priority).to eq(100)
    end
  end
  
  describe "#priority" do
    it "defaults to 0" do
      resolver = test_resolver.new(name: :test)
      expect(resolver.priority).to eq(0)
    end
  end
end

RSpec.describe RAAF::PromptResolverRegistry do
  let(:registry) { RAAF::PromptResolverRegistry.new }
  
  let(:high_priority_resolver) do
    Class.new(RAAF::PromptResolver) do
      def can_resolve?(spec)
        spec == "test"
      end
      
      def resolve(spec, context = {})
        RAAF::Prompt.new(id: "high")
      end
    end.new(name: :high, priority: 100)
  end
  
  let(:low_priority_resolver) do
    Class.new(RAAF::PromptResolver) do
      def can_resolve?(spec)
        spec == "test"
      end
      
      def resolve(spec, context = {})
        RAAF::Prompt.new(id: "low")
      end
    end.new(name: :low, priority: 10)
  end
  
  describe "#register" do
    it "registers resolvers sorted by priority" do
      registry.register(low_priority_resolver)
      registry.register(high_priority_resolver)
      
      resolvers = registry.resolvers
      expect(resolvers.first.name).to eq(:high)
      expect(resolvers.last.name).to eq(:low)
    end
  end
  
  describe "#unregister" do
    it "removes resolver by name" do
      registry.register(high_priority_resolver)
      expect(registry.resolvers).to include(high_priority_resolver)
      
      registry.unregister(:high)
      expect(registry.resolvers).not_to include(high_priority_resolver)
    end
  end
  
  describe "#resolve" do
    it "uses highest priority resolver that can handle spec" do
      registry.register(low_priority_resolver)
      registry.register(high_priority_resolver)
      
      result = registry.resolve("test")
      expect(result.id).to eq("high")
    end
    
    it "returns nil if no resolver can handle spec" do
      result = registry.resolve("unknown")
      expect(result).to be_nil
    end
  end
end