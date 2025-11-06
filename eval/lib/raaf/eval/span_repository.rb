# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # Repository for accessing and querying span data
    #
    # This class provides methods to find and filter spans for evaluation.
    # In a full implementation, this would connect to the database/storage system.
    class SpanRepository
      class << self
        ##
        # Finds a span by ID
        #
        # @param span_id [String] the span ID
        # @return [Hash] the span data
        # @raise [SpanNotFoundError] if span not found
        def find(span_id)
          span = stored_spans[span_id]
          raise SpanNotFoundError, "Span #{span_id} not found" unless span

          span
        end

        ##
        # Finds the latest span for an agent
        #
        # @param agent [String] the agent name
        # @return [Hash] the span data
        # @raise [SpanNotFoundError] if no span found
        def latest(agent:)
          spans = stored_spans.values.select { |s| s[:agent_name] == agent }
          spans = spans.sort_by { |s| s[:timestamp] || Time.now }.reverse

          span = spans.first
          raise SpanNotFoundError, "No span found for agent #{agent}" unless span

          span
        end

        ##
        # Queries spans with filters
        #
        # @param filters [Hash] filtering criteria
        # @return [Array<Hash>] matching spans
        def query(**filters)
          results = stored_spans.values

          results = results.select { |s| s[:agent_name] == filters[:agent] } if filters[:agent]
          results = results.select { |s| s[:model] == filters[:model] } if filters[:model]
          results = results.select { |s| s[:success] == filters[:success] } if filters.key?(:success)

          if filters[:from]
            from_time = filters[:from].is_a?(Time) ? filters[:from] : Time.parse(filters[:from])
            results = results.select { |s| (s[:timestamp] || Time.now) >= from_time }
          end

          if filters[:to]
            to_time = filters[:to].is_a?(Time) ? filters[:to] : Time.parse(filters[:to])
            results = results.select { |s| (s[:timestamp] || Time.now) <= to_time }
          end

          results
        end

        ##
        # Stores a span (for testing)
        #
        # @param span_id [String] the span ID
        # @param span_data [Hash] the span data
        def store(span_id, span_data)
          stored_spans[span_id] = span_data.merge(id: span_id, timestamp: span_data[:timestamp] || Time.now)
        end

        ##
        # Clears all stored spans (for testing)
        def clear!
          @stored_spans = {}
        end

        private

        def stored_spans
          @stored_spans ||= {}
        end
      end
    end
  end
end
