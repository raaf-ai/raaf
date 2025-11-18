# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # RAG (Retrieval-Augmented Generation) specific matchers
        module RAGMatchers
          include Base

          ##
          # Matcher for contextual relevancy score threshold
          ::RSpec::Matchers.define :have_high_contextual_relevancy do |min_score: 0.75|
            match do |result|
              return false unless result[:details]&.[](:method) == "contextual_relevancy"

              result[:score] >= min_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected contextual relevancy score to be at least #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end

            failure_message_when_negated do |result|
              "Expected contextual relevancy score to be below #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end
          end

          ##
          # Matcher for contextual precision score threshold
          ::RSpec::Matchers.define :have_high_precision do |min_score: 0.75|
            match do |result|
              return false unless result[:details]&.[](:method) == "contextual_precision"

              result[:score] >= min_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected contextual precision score to be at least #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end

            failure_message_when_negated do |result|
              "Expected contextual precision score to be below #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end
          end

          ##
          # Matcher for contextual recall score threshold
          ::RSpec::Matchers.define :have_high_recall do |min_score: 0.75|
            match do |result|
              return false unless result[:details]&.[](:method) == "contextual_recall"

              result[:score] >= min_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected contextual recall score to be at least #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end

            failure_message_when_negated do |result|
              "Expected contextual recall score to be below #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end
          end

          ##
          # Matcher to check minimal irrelevant documents in precision evaluation
          ::RSpec::Matchers.define :have_minimal_irrelevant_documents do |max_count: 2|
            match do |result|
              return false unless result[:details]&.[](:method) == "contextual_precision"

              irrelevant_count = result[:details][:irrelevant_count] || 0
              irrelevant_count <= max_count
            end

            failure_message do |result|
              irrelevant = result[:details][:irrelevant_count] || 0
              "Expected at most #{max_count} irrelevant documents, but got #{irrelevant}"
            end

            failure_message_when_negated do |result|
              irrelevant = result[:details][:irrelevant_count] || 0
              "Expected more than #{max_count} irrelevant documents, but got #{irrelevant}"
            end
          end

          ##
          # Matcher to check minimal missed relevant documents in recall evaluation
          ::RSpec::Matchers.define :have_minimal_missed_documents do |max_count: 1|
            match do |result|
              return false unless result[:details]&.[](:method) == "contextual_recall"

              missed_count = result[:details][:missed_relevant_count] || 0
              missed_count <= max_count
            end

            failure_message do |result|
              missed = result[:details][:missed_relevant_count] || 0
              "Expected at most #{max_count} missed relevant documents, but got #{missed}"
            end

            failure_message_when_negated do |result|
              missed = result[:details][:missed_relevant_count] || 0
              "Expected more than #{max_count} missed relevant documents, but got #{missed}"
            end
          end

          ##
          # Matcher to validate complete RAG result structure
          ::RSpec::Matchers.define :be_valid_rag_result do
            match do |result|
              # Check standard result structure
              return false unless result[:label] && result[:score] && result[:message] && result[:details]

              # Check RAG-specific method
              method = result[:details][:method]
              return false unless %w[contextual_relevancy contextual_precision contextual_recall].include?(method)

              # Check common RAG fields
              details = result[:details]
              return false unless details[:evaluated_field]
              return false unless details[:query].is_a?(String)

              # Method-specific validation
              case method
              when "contextual_relevancy"
                validate_relevancy_result(details)
              when "contextual_precision"
                validate_precision_result(details)
              when "contextual_recall"
                validate_recall_result(details)
              else
                false
              end
            end

            def validate_relevancy_result(details)
              details[:context_preview].is_a?(String) &&
                details[:context_length].is_a?(Integer) &&
                details[:relevancy_reasoning].is_a?(String)
            end

            def validate_precision_result(details)
              details[:document_count].is_a?(Integer) &&
                details[:relevant_count].is_a?(Integer) &&
                details[:irrelevant_count].is_a?(Integer) &&
                details[:document_relevance].is_a?(Array)
            end

            def validate_recall_result(details)
              details[:retrieved_count].is_a?(Integer) &&
                details[:available_count].is_a?(Integer) &&
                details[:relevant_count].is_a?(Integer) &&
                details[:retrieved_relevant_count].is_a?(Integer) &&
                details[:missed_relevant_count].is_a?(Integer) &&
                details[:document_analysis].is_a?(Array)
            end

            failure_message do |result|
              issues = []

              issues << "Missing label" unless result[:label]
              issues << "Missing score" unless result[:score]
              issues << "Missing message" unless result[:message]
              issues << "Missing details" unless result[:details]

              if result[:details]
                details = result[:details]
                method = details[:method]

                issues << "Missing evaluated_field" unless details[:evaluated_field]
                issues << "Invalid method (must be contextual_relevancy, contextual_precision, or contextual_recall)" unless %w[contextual_relevancy contextual_precision contextual_recall].include?(method)
                issues << "Missing or invalid query" unless details[:query].is_a?(String)

                case method
                when "contextual_relevancy"
                  issues << "Missing context_preview" unless details[:context_preview].is_a?(String)
                  issues << "Missing context_length" unless details[:context_length].is_a?(Integer)
                  issues << "Missing relevancy_reasoning" unless details[:relevancy_reasoning].is_a?(String)
                when "contextual_precision"
                  issues << "Missing document_count" unless details[:document_count].is_a?(Integer)
                  issues << "Missing relevant_count" unless details[:relevant_count].is_a?(Integer)
                  issues << "Missing irrelevant_count" unless details[:irrelevant_count].is_a?(Integer)
                  issues << "Missing document_relevance array" unless details[:document_relevance].is_a?(Array)
                when "contextual_recall"
                  issues << "Missing retrieved_count" unless details[:retrieved_count].is_a?(Integer)
                  issues << "Missing available_count" unless details[:available_count].is_a?(Integer)
                  issues << "Missing relevant_count" unless details[:relevant_count].is_a?(Integer)
                  issues << "Missing retrieved_relevant_count" unless details[:retrieved_relevant_count].is_a?(Integer)
                  issues << "Missing missed_relevant_count" unless details[:missed_relevant_count].is_a?(Integer)
                  issues << "Missing document_analysis array" unless details[:document_analysis].is_a?(Array)
                end
              end

              "Expected valid RAG result, but found issues:\n#{issues.map { |i| "  - #{i}" }.join("\n")}"
            end

            failure_message_when_negated do |result|
              "Expected invalid RAG result, but result structure was valid"
            end
          end

          ##
          # Matcher to check F1 score (harmonic mean of precision and recall)
          ::RSpec::Matchers.define :have_high_f1_score do |min_f1: 0.75|
            match do |results|
              precision_result, recall_result = results
              return false unless precision_result[:details]&.[](:method) == "contextual_precision"
              return false unless recall_result[:details]&.[](:method) == "contextual_recall"

              precision = precision_result[:score]
              recall = recall_result[:score]

              return false if precision.zero? && recall.zero?

              @f1_score = 2.0 * (precision * recall) / (precision + recall)
              @precision = precision
              @recall = recall
              @f1_score >= min_f1
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |results|
              "Expected F1 score to be at least #{format_percent(min_f1)}, " \
                "but got #{format_percent(@f1_score)} " \
                "(precision: #{format_percent(@precision)}, recall: #{format_percent(@recall)})"
            end

            failure_message_when_negated do |results|
              "Expected F1 score to be below #{format_percent(min_f1)}, " \
                "but got #{format_percent(@f1_score)}"
            end
          end

          ##
          # Matcher to check that all RAG metrics meet thresholds
          ::RSpec::Matchers.define :meet_all_rag_thresholds do |relevancy: 0.75, precision: 0.75, recall: 0.75|
            match do |results_hash|
              relevancy_result = results_hash[:relevancy] || results_hash["relevancy"]
              precision_result = results_hash[:precision] || results_hash["precision"]
              recall_result = results_hash[:recall] || results_hash["recall"]

              @failed_checks = []

              if relevancy_result
                unless relevancy_result[:score] >= relevancy
                  @failed_checks << "Relevancy: #{format_percent(relevancy_result[:score])} < #{format_percent(relevancy)}"
                end
              end

              if precision_result
                unless precision_result[:score] >= precision
                  @failed_checks << "Precision: #{format_percent(precision_result[:score])} < #{format_percent(precision)}"
                end
              end

              if recall_result
                unless recall_result[:score] >= recall
                  @failed_checks << "Recall: #{format_percent(recall_result[:score])} < #{format_percent(recall)}"
                end
              end

              @failed_checks.empty?
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |results_hash|
              "Expected all RAG metrics to meet thresholds, but failed checks:\n" \
                "#{@failed_checks.map { |c| "  - #{c}" }.join("\n")}"
            end

            failure_message_when_negated do |results_hash|
              "Expected some RAG metrics to fail thresholds, but all passed"
            end
          end

          ##
          # Matcher to verify document retrieval efficiency (precision vs recall trade-off)
          ::RSpec::Matchers.define :have_balanced_retrieval do |tolerance: 0.15|
            match do |results|
              precision_result, recall_result = results
              return false unless precision_result[:details]&.[](:method) == "contextual_precision"
              return false unless recall_result[:details]&.[](:method) == "contextual_recall"

              precision = precision_result[:score]
              recall = recall_result[:score]

              @difference = (precision - recall).abs
              @precision = precision
              @recall = recall
              @difference <= tolerance
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |results|
              "Expected precision and recall to be balanced (within #{format_percent(tolerance)}), " \
                "but difference was #{format_percent(@difference)} " \
                "(precision: #{format_percent(@precision)}, recall: #{format_percent(@recall)})"
            end

            failure_message_when_negated do |results|
              "Expected precision and recall to be imbalanced (difference > #{format_percent(tolerance)}), " \
                "but difference was only #{format_percent(@difference)}"
            end
          end
        end
      end
    end
  end
end
