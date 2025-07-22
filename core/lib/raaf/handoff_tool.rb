# frozen_string_literal: true

module RAAF

  ##
  # Creates handoff tools for agents to transfer execution
  #
  # This class generates function tools that agents can call to explicitly
  # hand off execution to other agents with structured data contracts.
  #
  class HandoffTool

    attr_reader :name, :target_agent, :description, :parameters, :handoff_context

    def initialize(name:, target_agent:, description:, parameters:, handoff_context:)
      @name = name
      @target_agent = target_agent
      @description = description
      @parameters = parameters
      @handoff_context = handoff_context
    end

    ##
    # Create a handoff tool for a specific agent
    #
    # @param target_agent [String] Name of the target agent
    # @param handoff_context [HandoffContext] Context for managing handoff
    # @param data_contract [Hash] Schema for handoff data
    # @return [FunctionTool] OpenAI function tool for handoff
    #
    def self.create_handoff_tool(target_agent:, handoff_context:, data_contract: {})
      tool_name = "handoff_to_#{target_agent.downcase.gsub(/[^a-z0-9_]/, "_")}"

      description = "Transfer execution to #{target_agent} with structured data"

      # Default parameters if none provided
      parameters = if data_contract.any?
                     data_contract
                   else
                     {
                       type: "object",
                       properties: {
                         data: {
                           type: "object",
                           description: "Data to pass to the target agent",
                           additionalProperties: true
                         },
                         reason: {
                           type: "string",
                           description: "Reason for the handoff"
                         }
                       },
                       required: ["data"],
                       additionalProperties: false
                     }
                   end

      handoff_proc = proc do |**args|
        execute_handoff(target_agent, handoff_context, args)
      end

      FunctionTool.new(
        handoff_proc,
        name: tool_name,
        description: description,
        parameters: parameters
      )
    end

    ##
    # Execute handoff function
    #
    # @param target_agent [String] Target agent name
    # @param handoff_context [HandoffContext] Handoff context
    # @param args [Hash] Handoff arguments
    # @return [String] JSON response
    #
    def self.execute_handoff(target_agent, handoff_context, args)
      # Extract data and reason from arguments
      data = args[:data] || args
      reason = args[:reason] || "Agent requested handoff"

      # Set up handoff context
      success = handoff_context.set_handoff(
        target_agent: target_agent,
        data: data,
        reason: reason
      )

      # Return structured response
      {
        success: success,
        handoff_prepared: true,
        target_agent: target_agent,
        timestamp: handoff_context.handoff_timestamp&.iso8601
      }.to_json
    end

    ##
    # Create structured data contract for search strategies
    #
    # @return [Hash] JSON schema for search handoff
    #
    def self.search_strategies_contract
      {
        type: "object",
        properties: {
          search_strategies: {
            type: "array",
            description: "Array of search strategies to be used",
            items: {
              type: "object",
              properties: {
                name: { type: "string", description: "Strategy name" },
                queries: {
                  type: "array",
                  items: { type: "string" },
                  description: "Search queries for this strategy"
                },
                priority: { type: "integer", description: "Strategy priority (1-10)" }
              },
              required: %w[name queries],
              additionalProperties: false
            }
          },
          market_insights: {
            type: "object",
            description: "Market insights discovered during search",
            properties: {
              trends: { type: "array", items: { type: "string" } },
              key_players: { type: "array", items: { type: "string" } },
              market_size: { type: "string" },
              growth_rate: { type: "string" }
            },
            additionalProperties: false
          },
          reason: {
            type: "string",
            description: "Reason for handoff"
          }
        },
        required: ["search_strategies"],
        additionalProperties: false
      }
    end

    ##
    # Create structured data contract for company discovery
    #
    # @return [Hash] JSON schema for company discovery handoff
    #
    def self.company_discovery_contract
      {
        type: "object",
        properties: {
          discovered_companies: {
            type: "array",
            description: "Companies discovered during research",
            items: {
              type: "object",
              properties: {
                name: { type: "string", description: "Company name" },
                industry: { type: "string", description: "Industry sector" },
                website: { type: "string", description: "Company website" },
                description: { type: "string", description: "Company description" },
                size: { type: "string", description: "Company size" },
                location: { type: "string", description: "Company location" },
                relevance_score: { type: "number", description: "Relevance score 0-1" }
              },
              required: %w[name industry],
              additionalProperties: false
            }
          },
          search_metadata: {
            type: "object",
            description: "Metadata about the search process",
            properties: {
              total_searches: { type: "integer" },
              strategies_used: { type: "array", items: { type: "string" } },
              completion_time: { type: "string" }
            },
            additionalProperties: false
          },
          workflow_status: {
            type: "string",
            enum: %w[completed partial failed],
            description: "Status of the workflow"
          }
        },
        required: %w[discovered_companies workflow_status],
        additionalProperties: false
      }
    end

    ##
    # Create workflow completion tool
    #
    # @param handoff_context [HandoffContext] Context for managing handoff
    # @param data_contract [Hash] Schema for completion data
    # @return [FunctionTool] OpenAI function tool for completion
    #
    def self.create_completion_tool(handoff_context:, data_contract: {})
      parameters = if data_contract.any?
                     data_contract
                   else
                     {
                       type: "object",
                       properties: {
                         status: {
                           type: "string",
                           enum: %w[completed failed],
                           description: "Workflow completion status"
                         },
                         results: {
                           type: "object",
                           description: "Final results",
                           additionalProperties: true
                         },
                         summary: {
                           type: "string",
                           description: "Summary of work completed"
                         }
                       },
                       required: ["status"],
                       additionalProperties: false
                     }
                   end

      completion_proc = proc do |**args|
        # Mark workflow as completed
        handoff_context.shared_context[:workflow_completed] = true
        handoff_context.shared_context[:final_results] = args

        {
          success: true,
          workflow_completed: true,
          status: args[:status],
          timestamp: Time.now.iso8601
        }.to_json
      end

      FunctionTool.new(
        completion_proc,
        name: "complete_workflow",
        description: "Mark the workflow as completed with final results",
        parameters: parameters
      )
    end

    # Alias for backward compatibility
    def self.discovery_data_contract
      company_discovery_contract
    end

    ##
    # Create structured data contract for workflow handoffs
    #
    # @return [Hash] JSON schema for workflow handoff
    #
    def self.workflow_handoff_contract
      {
        type: "object",
        properties: {
          workflow_step: {
            type: "string",
            description: "Current workflow step"
          },
          workflow_data: {
            type: "object",
            description: "Data from current workflow step",
            additionalProperties: true
          },
          next_steps: {
            type: "array",
            items: { type: "string" },
            description: "Remaining workflow steps"
          }
        },
        required: ["workflow_step", "workflow_data"],
        additionalProperties: false
      }
    end

    ##
    # Create structured data contract for user handoffs
    #
    # @return [Hash] JSON schema for user handoff
    #
    def self.user_handoff_contract
      {
        type: "object",
        properties: {
          user_id: {
            type: "string",
            description: "User identifier"
          },
          user_context: {
            type: "object",
            description: "User context information",
            additionalProperties: true
          },
          reason: {
            type: "string",
            description: "Reason for user handoff"
          }
        },
        required: ["user_id", "reason"],
        additionalProperties: false
      }
    end

    ##
    # Create structured data contract for task handoffs
    #
    # @return [Hash] JSON schema for task handoff
    #
    def self.task_handoff_contract
      {
        type: "object",
        properties: {
          task_id: {
            type: "string",
            description: "Task identifier"
          },
          task_type: {
            type: "string",
            description: "Type of task"
          },
          task_data: {
            type: "object",
            description: "Task-specific data",
            additionalProperties: true
          },
          priority: {
            type: "integer",
            minimum: 1,
            maximum: 10,
            description: "Task priority"
          }
        },
        required: ["task_id", "task_type"],
        additionalProperties: false
      }
    end

  end

end
