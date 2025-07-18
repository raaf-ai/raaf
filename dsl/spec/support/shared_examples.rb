# frozen_string_literal: true

# Shared examples for testing DSL modules
RSpec.shared_examples "a DSL module" do |dsl_module|
  it "can be included in a class" do
    test_class = Class.new do
      include dsl_module
    end

    expect(test_class.included_modules).to include(dsl_module)
  end

  it "extends the class with class methods when included" do
    test_class = Class.new do
      include dsl_module
    end

    expect(test_class).to respond_to(:_agent_config) if dsl_module == RAAF::DSL::AgentDsl
    expect(test_class).to respond_to(:_tool_config) if dsl_module == RAAF::DSL::ToolDsl
  end
end

# Shared examples for configuration management
RSpec.shared_examples "a configurable class" do
  it "has configuration attributes" do
    expect(described_class).to respond_to(:configuration)
  end

  it "allows configuration via block" do
    expect { described_class.configure { |config| } }.not_to raise_error # rubocop:disable Lint/EmptyBlock
  end
end

# Shared examples for base classes
RSpec.shared_examples "a base class" do
  it "can be subclassed" do
    subclass = Class.new(described_class)
    expect(subclass.superclass).to eq(described_class)
  end

  it "raises NotImplementedError for abstract methods" do
    abstract_methods = described_class.instance_methods(false).select do |method|
      instance = begin
        described_class.new
      rescue StandardError
        nil
      end
      next false unless instance

      begin
        instance.send(method)
        false
      rescue NotImplementedError
        true
      rescue ArgumentError
        # Method requires arguments, try with dummy args
        begin
          instance.send(method, {})
          false
        rescue NotImplementedError
          true
        rescue StandardError
          false
        end
      rescue StandardError
        false
      end
    end

    expect(abstract_methods).not_to be_empty if described_class.name.include?("Base")
  end
end

# Shared examples for agent classes
RSpec.shared_examples "an agent class" do
  let(:context) { { product: { name: "Test Product" } } }
  let(:processing_params) { { target_market: "Technology" } }

  it "accepts context and processing_params in initializer" do
    expect { described_class.new(context: context, processing_params: processing_params) }.not_to raise_error
  end

  it "stores context and processing_params" do
    agent = described_class.new(context: context, processing_params: processing_params)
    expect(agent.context.to_h).to eq(context)
    expect(agent.processing_params).to eq(processing_params)
  end
end

# Shared examples for prompt classes
RSpec.shared_examples "a prompt class" do
  it "can be initialized with keyword arguments" do
    expect { described_class.new(test_param: "value") }.not_to raise_error
  end

  it "validates contracts if configured" do
    prompt_class = Class.new(described_class) do
      requires :required_param
      contract_mode :strict
    end

    instance = prompt_class.new(optional_param: "value")
    expect { instance.validate! }.to raise_error(RAAF::DSL::Prompts::VariableContractError)
  end
end

# Shared examples for tool classes
RSpec.shared_examples "a tool class" do
  it "can be initialized with options" do
    expect { described_class.new(option: "value") }.not_to raise_error
  end

  it "has a tool_definition method" do
    tool = described_class.new
    expect(tool).to respond_to(:tool_definition)
  end
end

# Shared examples for generators
RSpec.shared_examples "a Rails generator" do
  it "inherits from Rails::Generators::Base or NamedBase" do
    expect(described_class.superclass.name).to match(/Rails::Generators::(Base|NamedBase)/)
  end

  it "has a description" do
    expect(described_class.desc).to be_a(String)
    expect(described_class.desc.length).to be > 0
  end

  it "has a source root" do
    expect(described_class.source_root).to be_a(String)
  end
end
