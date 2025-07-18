# frozen_string_literal: true

# Only load Rails generators if we're in a Rails environment
if defined?(Rails::Application) || ENV["RAILS_ENV"] || File.exist?("config/application.rb")
  begin
    require "rails"
    require "rails/generators/actions"
    require "rails/generators/named_base"
    # Flag indicating whether Rails generator dependencies are available
    # @api private
    AGENT_GENERATOR_RAILS_AVAILABLE = true
  rescue LoadError, NameError
    # Flag indicating whether Rails generator dependencies are available
    # @api private
    AGENT_GENERATOR_RAILS_AVAILABLE = false
  end
else
  # Flag indicating whether Rails generator dependencies are available
  # @api private
  AGENT_GENERATOR_RAILS_AVAILABLE = false
end

# Define minimal interface when Rails is not available
# This provides stub classes that allow the generator to be loaded and tested
# even when Rails is not available in the environment.
# @api private
unless AGENT_GENERATOR_RAILS_AVAILABLE
  # Minimal Rails module stub for non-Rails environments
  # @api private
  module Rails

    # Minimal Generators module stub
    # @api private
    module Generators

      # Returns empty array when Rails generators are not available
      # @api private
      def self.subclasses
        []
      end

      # Returns nil when Rails generators are not available
      # @api private
      def self.find_by_namespace(_name)
        nil
      end

      # Minimal NamedBase stub for testing without Rails
      # @api private
      class NamedBase

        # Stub implementation for source_root class method
        # @api private
        def self.source_root(path = nil)
          @source_root = path if path
          @source_root
        end

        # Stub implementation for desc class method
        # @api private
        def self.desc(description = nil)
          @desc = description if description
          @desc || "Rails generator"
        end

        # Stub implementation for namespace class method
        # @api private
        def self.namespace(name = nil)
          @namespace = name if name
          @namespace || "ai_agent_dsl:agent"
        end

        # Stub implementation for inherited callback
        # @api private

        # Stub implementation for initialize method
        # @api private
        def initialize(*args)
          # Minimal implementation for testing
        end

      end

    end

  end
end

module RAAF

  module DSL

    module Generators

      # Rails generator for creating AI agent classes and their corresponding prompt classes
      #
      # This generator creates two files for each AI agent:
      # 1. An agent class that inherits from RAAF::DSL::Agents::Base
      # 2. A corresponding prompt class that inherits from RAAF::DSL::Prompts::Base
      #
      # ## File Structure
      # For a simple agent name like "MarketResearch":
      # - `app/ai/agents/market_research.rb` - The agent class
      # - `app/ai/prompts/market_research.rb` - The prompt class
      #
      # For namespaced agents like "company/discovery":
      # - `app/ai/agents/company/discovery.rb` - The agent class
      # - `app/ai/prompts/company/discovery.rb` - The prompt class
      #
      # ## Generated Content
      # The generator creates:
      # - **Agent Class**: Includes DSL configuration with sample schema and tool usage
      # - **Prompt Class**: Includes variable contracts and system/user prompt methods
      # - **Proper Namespacing**: Handles nested modules for organized code structure
      # - **Documentation**: Adds helpful examples and method stubs
      #
      # ## Usage Examples
      #
      # @example Simple agent generation
      #   rails generate ai_agent_dsl:agent MarketResearch
      #   # Creates:
      #   # - app/ai/agents/market_research.rb (class MarketResearch)
      #   # - app/ai/prompts/market_research.rb (class MarketResearch)
      #
      # @example Namespaced agent generation
      #   rails generate ai_agent_dsl:agent company/discovery
      #   # Creates:
      #   # - app/ai/agents/company/discovery.rb (class Company::Discovery)
      #   # - app/ai/prompts/company/discovery.rb (class Company::Discovery)
      #
      # @example Multi-level namespacing
      #   rails generate ai_agent_dsl:agent sales/prospect/discovery
      #   # Creates:
      #   # - app/ai/agents/sales/prospect/discovery.rb (class Sales::Prospect::Discovery)
      #   # - app/ai/prompts/sales/prospect/discovery.rb (class Sales::Prospect::Discovery)
      #
      # ## Files Created
      # - Agent file with DSL configuration and schema definition
      # - Prompt file with variable contracts and prompt methods
      # - Proper directory structure (creates intermediate directories as needed)
      #
      # @see Rails::Generators::NamedBase Rails generator base class
      # @since 0.1.0
      #
      class AgentGenerator < Rails::Generators::NamedBase

        # Set the template directory for the generator
        # Templates are located in the same directory as this generator file
        source_root File.expand_path("templates", __dir__)

        # Description shown when running 'rails generate --help'
        desc "Generate an AI agent with DSL configuration"

        # Create the main agent class file
        #
        # This method generates the primary agent class that includes the AgentDsl
        # and provides the core functionality for the AI agent. The generated file
        # includes sample configuration, schema definition, and tool usage examples.
        #
        # The agent class inherits from RAAF::DSL::Agents::Base and includes
        # the RAAF::DSL::AgentDsl module for DSL functionality.
        def create_agent_file
          template "agent.rb.erb", "app/ai/agents/#{file_path}.rb"
        end

        # Create the corresponding prompt class file
        #
        # This method generates the prompt class that works with the agent.
        # The prompt class handles the generation of system and user prompts
        # with variable contracts and context mapping capabilities.
        #
        # The prompt class inherits from RAAF::DSL::Prompts::Base and provides
        # structured prompt building with variable validation.
        def create_prompt_file
          template "prompt.rb.erb", "app/ai/prompts/#{file_path}.rb"
        end

        private

        # Convert the provided name to an underscored file path
        #
        # This method handles the conversion from CamelCase or namespace/CamelCase
        # format to the appropriate file path for Rails conventions.
        #
        # @return [String] The underscored file path
        # @example Simple name conversion
        #   name = "MarketResearch"
        #   file_path # => "market_research"
        # @example Namespaced name conversion
        #   name = "company/discovery"
        #   file_path # => "company/discovery"
        def file_path
          name.underscore
        end

        # Get the full classified class name including namespaces
        #
        # @return [String] The full classified class name
        # @example Simple class name
        #   name = "market_research"
        #   class_path_name # => "MarketResearch"
        # @example Namespaced class name
        #   name = "company/discovery"
        #   class_path_name # => "Company::Discovery"
        def class_path_name
          name.classify
        end

        # Extract the module namespace from the agent name
        #
        # This method extracts the namespace portion of a namespaced agent name
        # and returns it as a properly formatted module name. Returns nil for
        # non-namespaced agents.
        #
        # @return [String, nil] The module namespace or nil if no namespace
        # @example With namespace
        #   name = "company/discovery"
        #   agent_module_name # => "Company"
        # @example Multi-level namespace
        #   name = "sales/prospect/discovery"
        #   agent_module_name # => "Sales::Prospect"
        # @example No namespace
        #   name = "market_research"
        #   agent_module_name # => nil
        def agent_module_name
          return unless name.include?("/")

          parts = name.split("/")
          parts[0..-2].map(&:classify).join("::")
        end

        # Extract the class name without namespace
        #
        # This method returns just the class name portion without any
        # namespace prefixes, properly classified for Ruby class naming.
        #
        # @return [String] The agent class name without namespace
        # @example With namespace
        #   name = "company/discovery"
        #   agent_class_name # => "Discovery"
        # @example Without namespace
        #   name = "market_research"
        #   agent_class_name # => "MarketResearch"
        def agent_class_name
          name.split("/").last.classify
        end

      end

    end

  end

end
