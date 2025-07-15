# frozen_string_literal: true

require_relative "raaf/tools/advanced/version"
require_relative "raaf/tools/advanced/computer_tool"
require_relative "raaf/tools/advanced/document_processor"
require_relative "raaf/tools/advanced/code_interpreter"
require_relative "raaf/tools/advanced/database_tool"
require_relative "raaf/tools/advanced/cloud_storage_tool"
require_relative "raaf/tools/advanced/api_client_tool"
require_relative "raaf/tools/advanced/workflow_tool"
require_relative "raaf/tools/advanced/data_analytics_tool"
require_relative "raaf/tools/advanced/enterprise_integrations"

module RubyAIAgentsFactory
  module Tools
    ##
    # Advanced enterprise tools for Ruby AI Agents Factory
    #
    # The Advanced module provides enterprise-grade tools for AI agents including:
    # - Computer control and automation
    # - Document processing (PDF, DOCX, Excel, etc.)
    # - Code interpretation and execution
    # - Database operations
    # - Cloud storage integration
    # - API client generation
    # - Workflow automation
    # - Data analytics and visualization
    # - Enterprise system integrations
    #
    # @example Computer automation
    #   computer = RubyAIAgentsFactory::Tools::Advanced::ComputerTool.new(
    #     display: ":0",
    #     browser: "chrome"
    #   )
    #   
    #   agent = RubyAIAgentsFactory::Agent.new(
    #     name: "AutomationAgent",
    #     instructions: "You can control the computer"
    #   )
    #   agent.add_tool(computer)
    #
    # @example Document processing
    #   doc_processor = RubyAIAgentsFactory::Tools::Advanced::DocumentProcessor.new(
    #     supported_formats: [:pdf, :docx, :xlsx, :pptx]
    #   )
    #   
    #   agent = RubyAIAgentsFactory::Agent.new(
    #     name: "DocumentAgent",
    #     instructions: "You can process documents"
    #   )
    #   agent.add_tool(doc_processor)
    #
    # @example Code interpretation
    #   code_interpreter = RubyAIAgentsFactory::Tools::Advanced::CodeInterpreter.new(
    #     languages: [:python, :ruby, :javascript],
    #     sandbox: true
    #   )
    #   
    #   agent = RubyAIAgentsFactory::Agent.new(
    #     name: "CodeAgent",
    #     instructions: "You can execute code"
    #   )
    #   agent.add_tool(code_interpreter)
    #
    # @example Database operations
    #   database = RubyAIAgentsFactory::Tools::Advanced::DatabaseTool.new(
    #     connection_string: "postgres://user:pass@localhost/db"
    #   )
    #   
    #   agent = RubyAIAgentsFactory::Agent.new(
    #     name: "DatabaseAgent",
    #     instructions: "You can query databases"
    #   )
    #   agent.add_tool(database)
    #
    # @example Enterprise integrations
    #   salesforce = RubyAIAgentsFactory::Tools::Advanced::EnterpriseIntegrations::SalesforceTool.new(
    #     client_id: "your_client_id",
    #     client_secret: "your_client_secret"
    #   )
    #   
    #   agent = RubyAIAgentsFactory::Agent.new(
    #     name: "SalesAgent",
    #     instructions: "You can interact with Salesforce"
    #   )
    #   agent.add_tool(salesforce)
    #
    # @since 1.0.0
    module Advanced
      # Error classes
      class AdvancedToolError < StandardError; end
      class SecurityError < AdvancedToolError; end
      class SandboxError < AdvancedToolError; end
      class IntegrationError < AdvancedToolError; end

      # Default configuration
      DEFAULT_CONFIG = {
        computer_control: {
          enabled: false,
          display: ":0",
          browser: "chrome",
          timeout: 30
        },
        code_interpreter: {
          enabled: true,
          sandbox: true,
          timeout: 60,
          memory_limit: "512MB",
          languages: [:python, :ruby, :javascript]
        },
        document_processor: {
          enabled: true,
          max_file_size: 50 * 1024 * 1024, # 50MB
          supported_formats: [:pdf, :docx, :xlsx, :pptx, :txt, :md]
        },
        database: {
          enabled: true,
          read_only: true,
          timeout: 30,
          max_results: 1000
        },
        cloud_storage: {
          enabled: true,
          providers: [:s3, :gcs, :azure],
          timeout: 60
        },
        security: {
          sandbox_all: true,
          network_isolation: true,
          file_system_isolation: true,
          allowed_domains: []
        }
      }.freeze

      class << self
        # @return [Hash] Current configuration
        attr_accessor :config

        ##
        # Configure advanced tools
        #
        # @param options [Hash] Configuration options
        # @yield [config] Configuration block
        #
        # @example Configure advanced tools
        #   RubyAIAgentsFactory::Tools::Advanced.configure do |config|
        #     config.computer_control.enabled = true
        #     config.code_interpreter.sandbox = true
        #     config.security.sandbox_all = true
        #   end
        #
        def configure
          @config ||= deep_dup(DEFAULT_CONFIG)
          yield @config if block_given?
          @config
        end

        ##
        # Get current configuration
        #
        # @return [Hash] Current configuration
        def config
          @config ||= deep_dup(DEFAULT_CONFIG)
        end

        ##
        # Check if a tool is enabled
        #
        # @param tool_name [Symbol] Tool name
        # @return [Boolean] True if tool is enabled
        def enabled?(tool_name)
          config.dig(tool_name, :enabled) || false
        end

        ##
        # Enable a tool
        #
        # @param tool_name [Symbol] Tool name
        def enable!(tool_name)
          config[tool_name] ||= {}
          config[tool_name][:enabled] = true
        end

        ##
        # Disable a tool
        #
        # @param tool_name [Symbol] Tool name
        def disable!(tool_name)
          config[tool_name] ||= {}
          config[tool_name][:enabled] = false
        end

        ##
        # Create a computer control tool
        #
        # @param options [Hash] Tool options
        # @return [ComputerTool] Computer tool instance
        def create_computer_tool(**options)
          raise SecurityError, "Computer control is disabled" unless enabled?(:computer_control)
          
          ComputerTool.new(**config[:computer_control].merge(options))
        end

        ##
        # Create a document processor tool
        #
        # @param options [Hash] Tool options
        # @return [DocumentProcessor] Document processor instance
        def create_document_processor(**options)
          raise SecurityError, "Document processing is disabled" unless enabled?(:document_processor)
          
          DocumentProcessor.new(**config[:document_processor].merge(options))
        end

        ##
        # Create a code interpreter tool
        #
        # @param options [Hash] Tool options
        # @return [CodeInterpreter] Code interpreter instance
        def create_code_interpreter(**options)
          raise SecurityError, "Code interpretation is disabled" unless enabled?(:code_interpreter)
          
          CodeInterpreter.new(**config[:code_interpreter].merge(options))
        end

        ##
        # Create a database tool
        #
        # @param options [Hash] Tool options
        # @return [DatabaseTool] Database tool instance
        def create_database_tool(**options)
          raise SecurityError, "Database access is disabled" unless enabled?(:database)
          
          DatabaseTool.new(**config[:database].merge(options))
        end

        ##
        # Create a cloud storage tool
        #
        # @param options [Hash] Tool options
        # @return [CloudStorageTool] Cloud storage tool instance
        def create_cloud_storage_tool(**options)
          raise SecurityError, "Cloud storage is disabled" unless enabled?(:cloud_storage)
          
          CloudStorageTool.new(**config[:cloud_storage].merge(options))
        end

        ##
        # Get available enterprise integrations
        #
        # @return [Array<Symbol>] Available integrations
        def available_integrations
          EnterpriseIntegrations.available_integrations
        end

        ##
        # Create an enterprise integration tool
        #
        # @param integration [Symbol] Integration name
        # @param options [Hash] Integration options
        # @return [Object] Integration tool instance
        def create_integration(integration, **options)
          EnterpriseIntegrations.create_integration(integration, **options)
        end

        ##
        # Validate security settings
        #
        # @raise [SecurityError] If security validation fails
        def validate_security!
          return if config[:security][:sandbox_all]
          
          enabled_tools = config.select { |_, tool_config| tool_config[:enabled] }
          dangerous_tools = enabled_tools.keys & [:computer_control, :code_interpreter]
          
          if dangerous_tools.any?
            raise SecurityError, "Dangerous tools enabled without sandboxing: #{dangerous_tools.join(', ')}"
          end
        end

        ##
        # Get tool statistics
        #
        # @return [Hash] Tool usage statistics
        def stats
          {
            enabled_tools: config.select { |_, tool_config| tool_config[:enabled] }.keys,
            total_tools: config.keys.size,
            security_enabled: config[:security][:sandbox_all],
            available_integrations: available_integrations.size
          }
        end

        private

        def deep_dup(hash)
          hash.each_with_object({}) do |(key, value), result|
            result[key] = value.is_a?(Hash) ? deep_dup(value) : value.dup
          end
        rescue TypeError
          hash
        end
      end
    end
  end
end