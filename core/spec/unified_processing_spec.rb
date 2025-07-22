# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/raaf/step_result'
require_relative '../lib/raaf/processed_response'
require_relative '../lib/raaf/response_processor'
require_relative '../lib/raaf/tool_use_tracker'
require_relative '../lib/raaf/step_processor'
require_relative '../lib/raaf/unified_step_executor'

RSpec.describe 'Unified Processing System' do
  let(:mock_agent) { double('Agent', name: 'TestAgent', tools: [], handoffs: []) }
  let(:mock_context) { double('RunContextWrapper') }
  let(:mock_runner) { double('Runner') }
  let(:mock_config) { double('RunConfig') }

  describe RAAF::StepResult do
    let(:step_result) do
      RAAF::StepResult.new(
        original_input: 'Hello',
        model_response: { content: 'Hi there' },
        pre_step_items: [{ type: 'message', content: 'Previous' }],
        new_step_items: [{ type: 'message', content: 'Current' }],
        next_step: RAAF::NextStepRunAgain.new
      )
    end

    it 'creates immutable step results' do
      expect(step_result.original_input).to eq('Hello')
      expect(step_result.generated_items.size).to eq(2)
      expect(step_result.should_continue?).to be(true)
      expect(step_result.final_output?).to be(false)
      expect(step_result.handoff_occurred?).to be(false)
    end

    it 'handles final output results' do
      final_result = RAAF::StepResult.new(
        original_input: 'Hello',
        model_response: {},
        pre_step_items: [],
        new_step_items: [],
        next_step: RAAF::NextStepFinalOutput.new('Final answer')
      )

      expect(final_result.final_output?).to be(true)
      expect(final_result.final_output).to eq('Final answer')
    end

    it 'handles handoff results' do
      target_agent = double('Agent', name: 'TargetAgent')
      handoff_result = RAAF::StepResult.new(
        original_input: 'Hello',
        model_response: {},
        pre_step_items: [],
        new_step_items: [],
        next_step: RAAF::NextStepHandoff.new(target_agent)
      )

      expect(handoff_result.handoff_occurred?).to be(true)
      expect(handoff_result.handoff_agent).to eq(target_agent)
    end
  end

  describe RAAF::ProcessedResponse do
    let(:processed_response) do
      RAAF::ProcessedResponse.new(
        new_items: [{ type: 'message' }],
        handoffs: [],
        functions: [double('ToolRun')],
        computer_actions: [],
        local_shell_calls: [],
        tools_used: ['get_weather']
      )
    end

    it 'categorizes response elements correctly' do
      expect(processed_response.has_tool_usage?).to be(true)
      expect(processed_response.has_handoffs?).to be(false)
      expect(processed_response.has_tools_or_actions_to_run?).to be(true)
      expect(processed_response.tools_used).to eq(['get_weather'])
    end

    it 'handles multiple handoffs' do
      handoff1 = double('Handoff1')
      handoff2 = double('Handoff2')
      
      multi_handoff_response = RAAF::ProcessedResponse.new(
        new_items: [],
        handoffs: [handoff1, handoff2],
        functions: [],
        computer_actions: [],
        local_shell_calls: [],
        tools_used: []
      )

      expect(multi_handoff_response.primary_handoff).to eq(handoff1)
      expect(multi_handoff_response.rejected_handoffs).to eq([handoff2])
    end
  end

  describe RAAF::ToolUseTracker do
    let(:tracker) { RAAF::ToolUseTracker.new }
    let(:agent) { double('Agent', name: 'TestAgent') }

    it 'tracks tool usage for agents' do
      expect(tracker.has_used_tools?(agent)).to be(false)
      
      tracker.add_tool_use(agent, ['get_weather', 'send_email'])
      
      expect(tracker.has_used_tools?(agent)).to be(true)
      expect(tracker.tools_used_by(agent)).to eq(['get_weather', 'send_email'])
      expect(tracker.total_tool_usage_count).to eq(2)
    end

    it 'handles duplicate tool names' do
      tracker.add_tool_use(agent, ['get_weather'])
      tracker.add_tool_use(agent, ['get_weather', 'send_email'])
      
      expect(tracker.tools_used_by(agent)).to eq(['get_weather', 'send_email'])
      expect(tracker.total_tool_usage_count).to eq(2)
    end

    it 'provides usage summary' do
      agent1 = double('Agent1', name: 'Agent1')
      agent2 = double('Agent2', name: 'Agent2')
      
      tracker.add_tool_use(agent1, ['tool1'])
      tracker.add_tool_use(agent2, ['tool2', 'tool3'])
      
      summary = tracker.usage_summary
      expect(summary).to eq('Agent1' => ['tool1'], 'Agent2' => ['tool2', 'tool3'])
    end
  end

  describe RAAF::UnifiedStepExecutor do
    let(:runner) { double('Runner') }
    let(:executor) { RAAF::UnifiedStepExecutor.new(runner: runner) }

    describe '#to_runner_format' do
      it 'converts StepResult to runner format' do
        step_result = RAAF::StepResult.new(
          original_input: 'Hello',
          model_response: {},
          pre_step_items: [],
          new_step_items: [{ type: 'message', content: 'Response' }],
          next_step: RAAF::NextStepFinalOutput.new('Final')
        )

        runner_format = executor.to_runner_format(step_result)
        
        expect(runner_format).to include(
          done: true,
          handoff: nil,
          generated_items: [{ type: 'message', content: 'Response' }],
          final_output: 'Final',
          should_continue: false
        )
      end

      it 'handles handoff results in runner format' do
        target_agent = double('Agent', name: 'TargetAgent')
        handoff_result = RAAF::StepResult.new(
          original_input: 'Hello',
          model_response: {},
          pre_step_items: [],
          new_step_items: [],
          next_step: RAAF::NextStepHandoff.new(target_agent)
        )

        runner_format = executor.to_runner_format(handoff_result)
        
        expect(runner_format[:handoff]).to eq({ assistant: 'TargetAgent' })
        expect(runner_format[:done]).to be(false)
      end
    end
  end

  describe 'Error Handling' do
    describe RAAF::Errors::ModelBehaviorError do
      it 'captures model response context' do
        response = { error: 'Invalid format' }
        error = RAAF::Errors::ModelBehaviorError.new(
          'Model returned invalid response',
          model_response: response,
          agent: mock_agent
        )

        expect(error.message).to eq('Model returned invalid response')
        expect(error.model_response).to eq(response)
        expect(error.agent).to eq(mock_agent)
      end
    end

    describe RAAF::Errors::ToolExecutionError do
      it 'captures tool execution context' do
        tool = double('Tool', name: 'get_weather')
        arguments = { location: 'NYC' }
        original_error = StandardError.new('Network timeout')

        error = RAAF::Errors::ToolExecutionError.new(
          'Tool execution failed',
          tool: tool,
          tool_arguments: arguments,
          original_error: original_error,
          agent: mock_agent
        )

        expect(error.tool_name).to eq('get_weather')
        expect(error.tool_arguments).to eq(arguments)
        expect(error.original_error).to eq(original_error)
      end
    end

    describe RAAF::ErrorHandling do
      describe '.validate_model_response' do
        it 'validates non-nil response' do
          expect {
            RAAF::ErrorHandling.validate_model_response(nil, mock_agent)
          }.to raise_error(RAAF::Errors::ModelBehaviorError, /Model response is nil/)
        end

        it 'validates hash structure' do
          expect {
            RAAF::ErrorHandling.validate_model_response('not a hash', mock_agent)
          }.to raise_error(RAAF::Errors::ModelBehaviorError, /not a hash/)
        end

        it 'validates content structure' do
          expect {
            RAAF::ErrorHandling.validate_model_response({}, mock_agent)
          }.to raise_error(RAAF::Errors::ModelBehaviorError, /missing expected content/)
        end

        it 'passes valid responses' do
          valid_response = { output: [{ type: 'message', content: 'Hello' }] }
          expect {
            RAAF::ErrorHandling.validate_model_response(valid_response, mock_agent)
          }.not_to raise_error
        end
      end

      describe '.safe_agent_name' do
        it 'handles various agent identifier formats' do
          expect(RAAF::ErrorHandling.safe_agent_name(nil)).to be_nil
          expect(RAAF::ErrorHandling.safe_agent_name('AgentName')).to eq('AgentName')
          
          agent_obj = double('Agent', name: 'ObjectAgent')
          expect(RAAF::ErrorHandling.safe_agent_name(agent_obj)).to eq('ObjectAgent')
        end
      end
    end
  end
end