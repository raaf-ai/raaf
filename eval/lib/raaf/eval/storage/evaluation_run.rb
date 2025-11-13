# frozen_string_literal: true

module RAAF
  module Eval
    module Storage
      # Chainable relation for building queries
      class EvaluationRunRelation
        def initialize(runs)
          @runs = runs.dup
        end

        def order(field_hash)
          field, direction = field_hash.first
          sorted = @runs.sort_by { |r| r.public_send(field) }
          @runs = direction == :desc ? sorted.reverse : sorted
          self
        end

        def limit(count)
          @runs = @runs.first(count)
          self
        end

        def to_a
          @runs
        end

        def first(count = 1)
          count == 1 ? @runs.first : @runs.first(count)
        end

        def last(count = 1)
          count == 1 ? @runs.last : @runs.last(count)
        end

        def size
          @runs.size
        end

        def map(&block)
          @runs.map(&block)
        end

        def each(&block)
          @runs.each(&block)
        end

        include Enumerable
        def each
          @runs.each { |run| yield run }
        end
      end

      # In-memory storage model for evaluation runs
      # Provides Active Record-like interface without database dependency
      class EvaluationRun
        attr_accessor :id, :evaluator_name, :configuration_name, :span_id,
                      :created_at, :tags, :result_data, :field_results,
                      :overall_passed, :aggregate_score, :duration_ms, :insertion_order

        # Class-level storage
        @@runs = []
        @@next_id = 1
        @@insertion_sequence = 0

        # Create a new evaluation run and persist it
        # @param attributes [Hash] Run attributes
        # @return [EvaluationRun] The created run
        def self.create!(attributes)
          run = new(attributes)
          run.id = @@next_id
          @@next_id += 1
          run.created_at ||= Time.now
          run.insertion_order = @@insertion_sequence
          @@insertion_sequence += 1
          @@runs << run
          run
        end

        # Get all evaluation runs
        # @return [Array<EvaluationRun>] All runs
        def self.all
          @@runs.dup
        end

        # Find run by ID
        # @param id [Integer] The run ID
        # @return [EvaluationRun, nil] The found run or nil
        def self.find(id)
          @@runs.find { |r| r.id == id }
        end

        # Filter runs by conditions
        # @param conditions [Hash] Field => value conditions
        # @return [Array<EvaluationRun>] Matching runs
        def self.where(conditions)
          @@runs.select do |run|
            conditions.all? do |key, value|
              run.public_send(key) == value
            end
          end
        end

        # Order runs by field
        # @param field_hash [Hash] Field => direction (:asc or :desc)
        # @return [EvaluationRunRelation] Chainable relation
        def self.order(field_hash)
          EvaluationRunRelation.new(@@runs).order(field_hash)
        end

        # Limit number of returned runs
        # @param count [Integer] Maximum number of runs
        # @return [EvaluationRunRelation] Chainable relation
        def self.limit(count)
          EvaluationRunRelation.new(@@runs).limit(count)
        end

        # Destroy all runs and reset ID sequence
        def self.destroy_all
          @@runs.clear
          @@next_id = 1
          @@insertion_sequence = 0
        end

        # Initialize a new evaluation run
        # @param attributes [Hash] Run attributes
        def initialize(attributes = {})
          attributes.each do |key, value|
            public_send("#{key}=", value) if respond_to?("#{key}=")
          end
        end

        # Remove this run from storage
        def destroy
          @@runs.delete(self)
        end

        # Convert run to hash
        # @return [Hash] Run data as hash
        def to_h
          {
            id: id,
            evaluator_name: evaluator_name,
            configuration_name: configuration_name,
            span_id: span_id,
            created_at: created_at,
            tags: tags,
            result_data: result_data,
            field_results: field_results,
            overall_passed: overall_passed,
            aggregate_score: aggregate_score,
            duration_ms: duration_ms
          }
        end
      end
    end
  end
end
