# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # The recent spans a policy would grade, newest first.
      #
      # PolicyMatcher answers this in the direction the pipeline runs: a span
      # arrives and asks which policies want it. The policy page needs the
      # reverse — given a policy, which spans could it grade right now — so a
      # prompt change can be checked against real traffic instead of waiting
      # for the sampler to reach the next span on its own.
      #
      # The matching is not reimplemented. SQL only narrows the candidates;
      # every survivor is still handed to EvaluationPolicy#matches_span? with
      # the attributes PolicyMatcher would have extracted, so this list cannot
      # come to disagree with what the pipeline does.
      #
      # Two kinds of span are dropped before matching:
      #
      # - Spans with no recorded response. EvaluationJob builds the data an
      #   evaluator selects from out of `agent.final_agent_response`, so a span
      #   without one produces an error rather than a score. Offering a button
      #   that can only fail is worse than showing a shorter list.
      # - Spans an evaluation produced. PolicyMatcher already refuses to grade
      #   those to keep evaluation from feeding on itself, and re-running an
      #   evaluator over its own replay measures nothing.
      class PolicySpanLookup
        # How many spans the panel offers. Enough to pick a representative one,
        # short enough that the page stays a page.
        DEFAULT_LIMIT = 5

        # How far back to look, and how many candidates to examine when the
        # answer cannot be settled in SQL. Together they bound the worst case:
        # a policy naming an agent that never ran walks a month of spans rather
        # than the whole table.
        WINDOW = 30.days
        SCAN_LIMIT = 100

        RESPONSE_KEY = "agent.final_agent_response"

        # @param policy [RAAF::Eval::Models::EvaluationPolicy]
        # @param limit [Integer] how many spans to return
        # @return [Array<RAAF::Rails::Tracing::SpanRecord>] newest first
        def self.recent_for(policy, limit: DEFAULT_LIMIT)
          new(policy).recent(limit: limit)
        end

        def initialize(policy)
          @policy = policy
        end

        # @param limit [Integer]
        # @return [Array<RAAF::Rails::Tracing::SpanRecord>]
        def recent(limit: DEFAULT_LIMIT)
          matched = []

          candidates(limit).each do |span|
            break if matched.size >= limit

            matched << span if matches?(span)
          end

          matched
        end

        private

        attr_reader :policy

        # `kind` is spelled as a literal rather than as a bind parameter so the
        # planner can prove the partial index's predicate and use it: a bound
        # value is unknown when a generic plan is built, and without the index
        # this is a walk backwards through a month of spans, reading each row's
        # attributes to reject it.
        def candidates(limit)
          scope = RAAF::Rails::Tracing::SpanRecord
                  .where("kind = 'agent'")
                  .where(start_time: WINDOW.ago..)
                  .where("span_attributes ->> ? IS NOT NULL", RESPONSE_KEY)
                  .where("span_attributes ->> 'source' IS DISTINCT FROM 'evaluation_run'")
                  .order(start_time: :desc)
                  .limit(scan_depth(limit))

          return scope if literal_agent_names.empty?

          scope.where(
            "lower(coalesce(span_attributes ->> 'agent.name', span_attributes ->> 'agent_name')) IN (?)",
            literal_agent_names
          )
        end

        # How many rows to read to keep `limit` of them.
        #
        # When the policy's only condition is a plain agent name, SQL has
        # already answered the whole question and the Ruby pass cannot reject
        # anything, so reading a hundred rows to keep five would be a hundred
        # span_attributes documents fetched for nothing. A pattern anywhere puts
        # the decision back in Ruby, and then the scan window is what keeps the
        # answer complete rather than merely quick.
        def scan_depth(limit)
          settled_in_sql? ? limit : SCAN_LIMIT
        end

        def settled_in_sql?
          return false if literal_agent_names.empty?

          [policy.model_pattern, policy.version_pattern, policy.environment].all? do |pattern|
            pattern.blank? || pattern == "all"
          end
        end

        # The agent names a policy can be narrowed by in SQL: the plain ones.
        #
        # A policy may name several agents, may wildcard them, or may name none
        # at all and so match everything. Only a plain list can be pushed into
        # the query; anything else reads the window and lets #matches_span?
        # decide, which is the same answer for more work rather than a
        # different one.
        def literal_agent_names
          return @literal_agent_names if defined?(@literal_agent_names)

          @literal_agent_names = compute_literal_agent_names
        end

        def compute_literal_agent_names
          declared = policy.agent_name.to_s.strip
          return [] if declared.blank? || declared == "all"

          names = declared.split(",").map(&:strip).reject(&:blank?)
          return [] if names.empty? || names.any? { |name| name.include?("*") }

          names.map(&:downcase)
        end

        def matches?(span)
          policy.matches_span?(RAAF::Eval::Continuous::PolicyMatcher.new(span).span_attributes)
        end
      end
    end
  end
end
