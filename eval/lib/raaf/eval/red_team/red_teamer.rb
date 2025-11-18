# frozen_string_literal: true

require_relative "vulnerability"
require_relative "attack"
require_relative "rt_test_case"
require_relative "risk_assessment"

module RAAF
  module Eval
    module RedTeam
      # Main coordinator for red-teaming operations
      #
      # RedTeamer orchestrates vulnerability testing by:
      # 1. Synthesizing baseline attacks for specified vulnerabilities
      # 2. Enhancing attacks using specified attack methods
      # 3. Executing attacks against the target LLM via callback
      # 4. Evaluating responses to determine vulnerabilities
      # 5. Aggregating results into comprehensive risk assessment
      #
      # RedTeamer is stateful and supports attack caching for efficiency.
      #
      # @example Basic red-teaming
      #   red_teamer = RedTeamer.new(
      #     model_callback: ->(input) { my_agent.run(input) }
      #   )
      #
      #   assessment = red_teamer.scan(
      #     vulnerabilities: [:bias, :toxicity, :pii_leakage],
      #     attacks: [:prompt_injection, :roleplay],
      #     attacks_per_vulnerability: 5
      #   )
      #
      #   puts "Pass rate: #{assessment.overview.formatted_pass_rate}"
      #   puts "Critical vulnerabilities: #{assessment.critical_vulnerabilities}"
      #
      # @example With caching and async
      #   red_teamer = RedTeamer.new(
      #     model_callback: my_callback,
      #     async_mode: true,
      #     max_concurrent: 10
      #   )
      #
      #   # First scan generates attacks
      #   assessment1 = red_teamer.scan(
      #     vulnerabilities: [:bias],
      #     attacks: [:prompt_injection]
      #   )
      #
      #   # Second scan reuses cached attacks
      #   assessment2 = red_teamer.scan(
      #     vulnerabilities: [:bias],
      #     attacks: [:roleplay],
      #     reuse_previous_attacks: true  # Reuse baseline attacks
      #   )
      #
      class RedTeamer
        attr_reader :model_callback, :config, :attack_cache

        # Initialize red-teaming coordinator
        #
        # @param model_callback [Proc] Callback to query target model: ->(input) { output }
        #   Must accept exactly one String parameter and return a String.
        #   Can be async/await compatible.
        # @param async_mode [Boolean] Enable async execution (default: true)
        # @param max_concurrent [Integer] Max concurrent async operations (default: 10)
        # @param ignore_errors [Boolean] Continue on errors vs fail fast (default: true)
        # @param target_purpose [String] Description of target application's purpose
        # @param simulator_model [String] LLM model for attack generation (default: "gpt-4o")
        # @param config [Hash] Additional configuration options
        def initialize(
          model_callback:,
          async_mode: true,
          max_concurrent: 10,
          ignore_errors: true,
          target_purpose: nil,
          simulator_model: "gpt-4o",
          **config
        )
          @model_callback = validate_callback!(model_callback)
          @async_mode = async_mode
          @max_concurrent = max_concurrent
          @ignore_errors = ignore_errors
          @target_purpose = target_purpose
          @simulator_model = simulator_model
          @config = config
          @attack_cache = {}  # Cache: { vulnerability_type => [baseline_attacks] }
        end

        # Perform comprehensive red-teaming scan
        #
        # @param vulnerabilities [Array<Symbol, Vulnerability>] Vulnerabilities to test
        # @param attacks [Array<Symbol, Attack>] Attack methods to use
        # @param attacks_per_vulnerability [Integer] Number of attacks per vulnerability (default: 5)
        # @param reuse_previous_attacks [Boolean] Reuse cached baseline attacks (default: false)
        # @return [RiskAssessment] Comprehensive results and analysis
        def scan(
          vulnerabilities:,
          attacks:,
          attacks_per_vulnerability: 5,
          reuse_previous_attacks: false
        )
          # Convert symbols to vulnerability/attack instances
          vulnerability_instances = resolve_vulnerabilities(vulnerabilities)
          attack_instances = resolve_attacks(attacks)

          # Generate or retrieve baseline attacks
          baseline_attacks = if reuse_previous_attacks
                               retrieve_cached_attacks(vulnerability_instances)
                             else
                               generate_baseline_attacks(vulnerability_instances, attacks_per_vulnerability)
                             end

          # Execute attacks and collect test cases
          test_cases = execute_attacks(
            baseline_attacks: baseline_attacks,
            attack_methods: attack_instances,
            vulnerability_instances: vulnerability_instances
          )

          # Aggregate results into risk assessment
          RiskAssessment.new(test_cases: test_cases)
        end

        # Test a single vulnerability with specific attacks
        #
        # @param vulnerability [Symbol, Vulnerability] Vulnerability to test
        # @param attacks [Array<Symbol, Attack>] Attack methods to use
        # @param count [Integer] Number of test attempts (default: 5)
        # @return [Array<RTTestCase>] List of test cases
        def test_vulnerability(vulnerability:, attacks:, count: 5)
          vuln_instance = resolve_vulnerabilities([vulnerability]).first
          attack_instances = resolve_attacks(attacks)

          baseline_attacks = generate_baseline_attacks([vuln_instance], count)

          execute_attacks(
            baseline_attacks: baseline_attacks[vuln_instance.vulnerability_type],
            attack_methods: attack_instances,
            vulnerability_instances: [vuln_instance]
          )
        end

        # Clear cached baseline attacks
        #
        # Useful when target application changes or for testing fresh attack variations
        def clear_cache!
          @attack_cache.clear
        end

        # Get cached attacks for a vulnerability type
        #
        # @param vulnerability_type [String] Vulnerability type identifier
        # @return [Array<String>, nil] Cached attacks or nil
        def cached_attacks_for(vulnerability_type)
          @attack_cache[vulnerability_type]
        end

        private

        def validate_callback!(callback)
          unless callback.respond_to?(:call)
            raise ArgumentError, "model_callback must be callable (Proc or lambda)"
          end

          # Check arity (should accept 1 parameter)
          if callback.arity != 1 && callback.arity != -1
            raise ArgumentError, "model_callback must accept exactly one parameter"
          end

          callback
        end

        def resolve_vulnerabilities(vulnerabilities)
          vulnerabilities.map do |vuln|
            case vuln
            when Vulnerability
              vuln
            when Symbol, String
              # TODO: Load from vulnerability registry when implemented
              raise NotImplementedError, "Vulnerability registry not yet implemented. " \
                                         "Pass Vulnerability instances for now."
            else
              raise ArgumentError, "Invalid vulnerability type: #{vuln.class}"
            end
          end
        end

        def resolve_attacks(attacks)
          attacks.map do |attack|
            case attack
            when Attack
              attack
            when Symbol, String
              # TODO: Load from attack registry when implemented
              raise NotImplementedError, "Attack registry not yet implemented. " \
                                         "Pass Attack instances for now."
            else
              raise ArgumentError, "Invalid attack type: #{attack.class}"
            end
          end
        end

        def generate_baseline_attacks(vulnerability_instances, count)
          baseline_attacks = {}

          vulnerability_instances.each do |vuln|
            vuln_type = vuln.vulnerability_type

            # Generate baseline attacks for this vulnerability
            attacks = vuln.generate_baseline_attacks(count)

            # Cache for reuse
            @attack_cache[vuln_type] = attacks

            baseline_attacks[vuln_type] = attacks
          end

          baseline_attacks
        end

        def retrieve_cached_attacks(vulnerability_instances)
          baseline_attacks = {}

          vulnerability_instances.each do |vuln|
            vuln_type = vuln.vulnerability_type

            cached = @attack_cache[vuln_type]
            if cached.nil? || cached.empty?
              # No cache available, generate fresh attacks
              baseline_attacks[vuln_type] = vuln.generate_baseline_attacks(5)
            else
              baseline_attacks[vuln_type] = cached
            end
          end

          baseline_attacks
        end

        def execute_attacks(baseline_attacks:, attack_methods:, vulnerability_instances:)
          test_cases = []

          vulnerability_instances.each do |vuln|
            vuln_type = vuln.vulnerability_type
            baselines = baseline_attacks[vuln_type] || []

            baselines.each do |baseline|
              attack_methods.each do |attack|
                begin
                  test_case = execute_single_attack(
                    vulnerability: vuln,
                    attack: attack,
                    baseline_input: baseline
                  )
                  test_cases << test_case
                rescue StandardError => e
                  # Handle errors based on ignore_errors setting
                  if @ignore_errors
                    test_cases << create_error_test_case(vuln, attack, baseline, e)
                  else
                    raise e
                  end
                end
              end
            end
          end

          test_cases
        end

        def execute_single_attack(vulnerability:, attack:, baseline_input:)
          if attack.single_turn?
            execute_single_turn_attack(vulnerability, attack, baseline_input)
          else
            execute_multi_turn_attack(vulnerability, attack, baseline_input)
          end
        end

        def execute_single_turn_attack(vulnerability, attack, baseline_input)
          # Transform baseline input using attack method
          attack_input = attack.execute(baseline_input, context: build_context(vulnerability))

          # Query target model
          model_output = @model_callback.call(attack_input)

          # Assess vulnerability
          assessment = vulnerability.assess(attack_input, model_output, context: build_context(vulnerability))

          # Create test case
          RTTestCase.new(
            vulnerability: vulnerability,
            attack: attack,
            input: attack_input,
            output: model_output,
            score: assessment[:score],
            reasoning: assessment[:reasoning],
            status: assessment[:score] == 1.0 ? "passed" : "failed",
            vulnerable: assessment[:vulnerable],
            context: build_context(vulnerability)
          )
        end

        def execute_multi_turn_attack(vulnerability, attack, baseline_input)
          # Execute conversational attack
          turns = attack.execute_conversation(baseline_input, @model_callback, context: build_context(vulnerability))

          # Get final output for assessment
          final_output = turns.last[:output]
          initial_input = turns.first[:input]

          # Assess vulnerability based on conversation
          assessment = vulnerability.assess(initial_input, final_output, context: build_context(vulnerability))

          # Create test case
          RTTestCase.new(
            vulnerability: vulnerability,
            attack: attack,
            turns: turns,
            score: assessment[:score],
            reasoning: assessment[:reasoning],
            status: assessment[:score] == 1.0 ? "passed" : "failed",
            vulnerable: assessment[:vulnerable],
            context: build_context(vulnerability)
          )
        end

        def create_error_test_case(vulnerability, attack, baseline_input, error)
          RTTestCase.new(
            vulnerability: vulnerability,
            attack: attack,
            input: baseline_input,
            output: nil,
            score: 0.0,
            reasoning: "Error during execution: #{error.message}",
            status: "error",
            vulnerable: false,
            context: build_context(vulnerability).merge(error: error.message)
          )
        end

        def build_context(vulnerability)
          {
            target_purpose: @target_purpose,
            simulator_model: @simulator_model,
            vulnerability_type: vulnerability.vulnerability_type,
            category: vulnerability.category
          }.merge(@config)
        end
      end
    end
  end
end
