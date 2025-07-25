# frozen_string_literal: true

module RAAF
  module DSL
    module AgentDsl
      # Configuration methods for agent DSL
      module Configuration
        extend ActiveSupport::Concern

        class_methods do
          # Configure agent basic properties
          def agent_name(name = nil)
            if name
              _agent_config[:name] = name
            else
              _agent_config[:name]
            end
          end

          def model(model_name = nil)
            if model_name
              _agent_config[:model] = model_name
            else
              # Check YAML config first, then agent config, then default
              _agent_config[:model] ||
                RAAF::DSL::Config.model_for(agent_name) ||
                "gpt-4o"
            end
          end

          def max_turns(turns = nil)
            if turns
              _agent_config[:max_turns] = turns
            else
              # Check YAML config first, then agent config, then default
              _agent_config[:max_turns] ||
                RAAF::DSL::Config.max_turns_for(agent_name) ||
                3
            end
          end

          def description(desc = nil)
            if desc
              _agent_config[:description] = desc
            else
              _agent_config[:description]
            end
          end

          # Configure tool choice behavior for the agent
          def tool_choice(choice = nil)
            if choice
              # Handle simplified syntax for tool names
              _agent_config[:tool_choice] = if choice.is_a?(String) && !%w[auto none required].include?(choice)
                                              {
                                                type: "function",
                                                function: { name: choice }
                                              }
                                            else
                                              choice
                                            end
            else
              # Check YAML config first, then agent config, then framework default
              _agent_config[:tool_choice] ||
                RAAF::DSL::Config.tool_choice_for(agent_name) ||
                RAAF::DSL.configuration.default_tool_choice
            end
          end

          # Configure output format
          def output_format(format = nil)
            if format.nil?
              # Getter: return the configured output format
              _agent_config[:output_format]
            else
              # Setter: configure the output format
              case format.to_sym
              when :text, :plain, :unstructured
                _agent_config[:output_format] = :unstructured
              when :json, :structured, :schema
                _agent_config[:output_format] = :structured
              else
                raise ArgumentError,
                      "Invalid output format: #{format}. Use :text, :plain, :unstructured, " \
                      ":json, :structured, or :schema"
              end
            end
          end

          # Convenience methods for output format
          def text_output
            output_format(:text)
          end

          def structured_output
            output_format(:structured)
          end

          def unstructured_output
            output_format(:unstructured)
          end

          # Configure result storage for the agent
          def result_storage_enabled(enabled = nil)
            if enabled.nil?
              # Getter: return the configured setting, default to true
              _agent_config.fetch(:result_storage_enabled, true)
            else
              # Setter: configure the setting
              _agent_config[:result_storage_enabled] = enabled
            end
          end

          # Helper method to get agent name for YAML config lookup
          def inferred_agent_name
            agent_class_name = name

            # Remove the agent namespace and get just the class name
            # e.g., RAAF::DSL::Agents::Company::Discovery -> Company::Discovery
            class_path = if agent_class_name.start_with?("RAAF::DSL::Agents::")
                           agent_class_name.sub("RAAF::DSL::Agents::", "")
                         else
                           agent_class_name
                         end

            # Convert to underscore format for YAML config
            # e.g., Company::Discovery -> company_discovery
            # e.g., Product::MarketResearch -> market_research
            # e.g., Orchestrator -> orchestrator
            class_path.underscore.gsub("/", "_")
          end
        end
      end
    end
  end
end
