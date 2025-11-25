# frozen_string_literal: true

module RAAF
  module Eval
    module Continuous
      ##
      # PolicyMatcher determines which evaluation policies should be applied
      # to a given span based on targeting criteria and sampling rules.
      # This is the core component that bridges span creation with policy evaluation.
      #
      # @example Find policies for a span
      #   span = SpanRecord.last
      #   matcher = PolicyMatcher.new(span)
      #
      #   # Get all matching policies (before sampling)
      #   policies = matcher.matching_policies
      #
      #   # Get policies that should actually be evaluated (after sampling)
      #   to_evaluate = matcher.policies_to_evaluate
      #
      # @example Use in span creation hook
      #   class SpanRecord < ActiveRecord::Base
      #     after_commit :enqueue_continuous_evaluation, on: :create
      #
      #     def enqueue_continuous_evaluation
      #       matcher = PolicyMatcher.new(self)
      #       matcher.policies_to_evaluate.each do |policy|
      #         EvaluationJob.perform_later(self, policy)
      #       end
      #     end
      #   end
      #
      # @see EvaluationPolicy The policies being matched
      # @see EvaluationJob The job that processes matched policies
      class PolicyMatcher
        attr_reader :span

        ##
        # Initialize with a span to match against policies.
        #
        # @param span [Object] Span record or span-like object with agent_name, environment, model
        #
        # @example Initialize with a span record
        #   span = SpanRecord.find(123)
        #   matcher = PolicyMatcher.new(span)
        def initialize(span)
          @span = span
          @span_attributes = nil
        end

        ##
        # Find all matching policies that should trigger evaluation for this span.
        # Policies are matched based on agent name, environment, and model patterns.
        #
        # @return [Array<EvaluationPolicy>] Matching policies ordered by priority (highest first)
        #
        # @example Get matching policies
        #   matcher.matching_policies
        #   #=> [<Policy priority:100>, <Policy priority:80>, <Policy priority:50>]
        def matching_policies
          Models::EvaluationPolicy
            .active
            .by_priority
            .select { |policy| policy.matches_span?(span_attributes) }
        end

        ##
        # Get policies that should be evaluated after applying sampling rules
        # @return [Array<EvaluationPolicy>] Policies to evaluate
        def policies_to_evaluate
          matching_policies.select { |policy| should_evaluate?(policy) }
        end

        ##
        # Determine if a span should be evaluated for a given policy
        # based on sampling rules and daily limits
        # @param policy [EvaluationPolicy] Policy to check
        # @return [Boolean]
        def should_evaluate?(policy)
          return false if daily_limit_reached?(policy)

          case policy.sampling_mode
          when "all"
            true
          when "percentage"
            rand(100) < policy.sample_rate
          when "every_n"
            check_and_increment_counter(policy)
          else
            false
          end
        end

        private

        ##
        # Extract relevant attributes from span for policy matching
        # @return [Hash] Span attributes for matching
        def extract_span_attributes
          return @span_attributes if @span_attributes

          @span_attributes = {}

          # Try direct attribute access first
          %i[agent_name environment model version].each do |attr|
            @span_attributes[attr] = extract_attribute(attr)
          end

          @span_attributes
        end

        alias span_attributes extract_span_attributes

        ##
        # Extract a single attribute from the span
        # @param attr [Symbol] Attribute name
        # @return [Object] Attribute value
        def extract_attribute(attr)
          # Try direct method first
          if span.respond_to?(attr)
            return span.public_send(attr)
          end

          # Try span_data hash (for SpanRecord)
          if span.respond_to?(:span_data) && span.span_data.is_a?(Hash)
            data = span.span_data
            return data[attr.to_s] || data[attr]
          end

          # Try as hash
          if span.is_a?(Hash)
            return span[attr] || span[attr.to_s]
          end

          nil
        end

        ##
        # Check if daily evaluation limit has been reached
        # @param policy [EvaluationPolicy] Policy to check
        # @return [Boolean]
        def daily_limit_reached?(policy)
          return false if policy.max_daily_evaluations.nil?
          policy.at_daily_limit?
        end

        ##
        # Check counter for every_n sampling and increment if needed
        # @param policy [EvaluationPolicy] Policy with every_n sampling
        # @return [Boolean] true if this span should be sampled
        def check_and_increment_counter(policy)
          policy.should_sample?
        end
      end
    end
  end
end
