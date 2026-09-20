# frozen_string_literal: true

require "json"
require_relative "../decision_interface"

module RAAF

  module Models

    module Decision

      ##
      # A decision provider backed by an ordinary chat LLM
      #
      # This implements {RAAF::Models::DecisionInterface} on top of any model
      # RAAF can already talk to, by asking for the answers as JSON. It exists
      # so that code written against the decision interface runs without a
      # decision-model API key, and so that a purpose-built decision model can
      # be compared against the LLM it replaces.
      #
      # == The probabilities are not calibrated
      #
      # A chat model's self-reported probability is a token it generated, not a
      # calibrated estimate: it clusters on round numbers and shifts with
      # prompt wording. Purpose-built decision models are trained to emit
      # calibrated probabilities; this provider is not a substitute for that.
      # Treat its numbers as a baseline to compare against, and keep whatever
      # calibration step you would have applied to a raw LLM judge.
      #
      # @example Using it as the fallback when no decision API key is set
      #   provider = LLMBackedProvider.new(model: "gpt-4o")
      #   provider.noul(state: ticket, instructions: "The message conveys urgency").probability
      #
      class LLMBackedProvider < DecisionInterface

        # Model used when the caller names none
        DEFAULT_MODEL = "gpt-4o"

        # Temperature used for judging, kept at 0 for repeatability
        DEFAULT_TEMPERATURE = 0.0

        ##
        # @param model [String, nil] Chat model to ask (default: {DEFAULT_MODEL})
        # @param temperature [Float] Sampling temperature (default: {DEFAULT_TEMPERATURE})
        # @param runner [#run, nil] Runner to use instead of building one, for testing
        # @param options [Hash] Additional options passed to {DecisionInterface}
        #
        def initialize(model: nil, temperature: DEFAULT_TEMPERATURE, runner: nil, **)
          super(model: model, **)
          @temperature = temperature
          @runner = runner
        end

        ##
        # @return [String] The provider display name
        #
        def provider_name
          "LLMBacked"
        end

        ##
        # @return [String] {DEFAULT_MODEL}
        #
        def default_model
          DEFAULT_MODEL
        end

        ##
        # Asks the chat model for the answers as JSON
        #
        # @param state [String, Hash, Array] What to decide about
        # @param questions [Hash{String => Question}] Built questions by name
        # @param model [String, nil] Chat model to ask
        # @param kwargs [Hash] Additional parameters passed to the runner
        # @return [Result]
        # @raise [MalformedAnswerError] If the model's reply is not usable JSON
        #
        def perform_decision(state:, questions:, model:, **)
          content = ask_model(build_prompt(state, questions), model, **)
          parsed = RAAF::JsonRepair.repair(content)

          raise MalformedAnswerError, "#{provider_name} did not return JSON: #{content.to_s[0, 200]}" unless parsed.is_a?(Hash)

          answers = questions.each_with_object({}) do |(name, question), result|
            body = parsed[name] || parsed[name.to_sym]
            raise MalformedAnswerError, "#{provider_name} did not answer question #{name.inspect}" if body.nil?

            result[name] = question.parse(body)
          end

          Result.new(answers: answers, model: model, provider: provider_name, raw: parsed)
        end

        private

        ##
        # Runs the prompt through a RAAF agent
        #
        # @param prompt [String] The rendered prompt
        # @param model [String, nil] Chat model to ask
        # @param kwargs [Hash] Additional parameters passed to the runner
        # @return [String, nil] The model's reply
        #
        def ask_model(prompt, model, **)
          runner = @runner || build_runner(model)
          result = runner.run(prompt, temperature: @temperature, **)
          message = result.messages.last
          message && (message[:content] || message["content"])
        end

        ##
        # @param model [String, nil] Chat model to ask
        # @return [RAAF::Runner]
        #
        def build_runner(model)
          agent = RAAF::Agent.new(
            name: "DecisionModel",
            instructions: "You answer typed questions about a piece of state. Always reply with valid JSON and nothing else.",
            model: model || default_model
          )

          RAAF::Runner.new(agent: agent)
        end

        ##
        # Renders the state and questions, with the JSON shape each answer must take
        #
        # @param state [String, Hash, Array] What to decide about
        # @param questions [Hash{String => Question}] Built questions by name
        # @return [String]
        #
        def build_prompt(state, questions)
          <<~PROMPT
            Answer each question about the state below.

            ## State
            #{state.is_a?(String) ? state : JSON.pretty_generate(state)}

            ## Questions
            #{questions.map { |name, question| render_question(name, question) }.join("\n\n")}

            ## Response format
            Reply with a single JSON object keyed by question name, and nothing else:

            {
            #{questions.map { |name, question| "  #{name.to_json}: #{answer_shape(question)}" }.join(",\n")}
            }

            Probabilities are between 0.0 and 1.0. Probabilities over a set of
            options or levels must sum to 1.0. Report the probability you
            actually hold, including values near 0.5 when the state is
            genuinely ambiguous.
          PROMPT
        end

        ##
        # @param name [String] The question name
        # @param question [Question] The question
        # @return [String] The question rendered for the prompt
        #
        def render_question(name, question)
          lines = ["### #{name} (#{question.type})", question.instructions]
          lines << "Options: #{question.options.join(", ")}" if question.is_a?(Choice)
          lines << "Levels, lowest first: #{question.levels.join(", ")}" if question.is_a?(Score)
          lines.join("\n")
        end

        ##
        # @param question [Question] The question
        # @return [String] The JSON shape its answer must take
        #
        def answer_shape(question)
          case question
          when Noul
            '{"type": "noul", "noul": <probability the statement is true>}'
          when Choice
            '{"type": "choice", "choice": "<one option>", ' \
            '"probabilities": {"<option>": <probability>, ...}, "confidence": <0.0-1.0>}'
          when Score
            '{"type": "score", "score": <index into the levels, fractional allowed>, ' \
            '"level": "<one level>", "distribution": {"<level>": <probability>, ...}, ' \
            '"confidence": <0.0-1.0>}'
          end
        end

      end

    end

  end

end
