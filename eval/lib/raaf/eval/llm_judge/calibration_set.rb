# frozen_string_literal: true

module RAAF
  module Eval
    module LLMJudge
      ##
      # CalibrationSet manages ground-truth labeled data for LLM judge calibration.
      #
      # This class implements calibration data management as described in:
      # Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations" (arXiv:2511.21140)
      #
      # Calibration data is essential for computing sensitivity (true positive rate) and
      # specificity (true negative rate) of an LLM judge, which are required for
      # bias-corrected accuracy estimates.
      #
      # @example Creating a calibration set
      #   calibration = CalibrationSet.new
      #   calibration.add(input: "What is 2+2?", output: "4", ground_truth: true)
      #   calibration.add(input: "What is 2+2?", output: "5", ground_truth: false)
      #
      # @example Loading from file
      #   calibration = CalibrationSet.from_json("calibration_data.json")
      #
      # @see https://arxiv.org/abs/2511.21140
      # @see https://github.com/UW-Madison-Lee-Lab/LLM-judge-reporting
      #
      class CalibrationSet
        # @return [Array<Hash>] The calibration samples
        attr_reader :samples

        # @return [Hash] Metadata about the calibration set
        attr_reader :metadata

        ##
        # Creates a new calibration set
        #
        # @param samples [Array<Hash>] Initial samples (optional)
        # @param metadata [Hash] Metadata about the calibration set
        def initialize(samples: [], metadata: {})
          @samples = []
          @metadata = {
            created_at: Time.now.iso8601,
            version: "1.0.0",
            source: nil,
            description: nil
          }.merge(metadata)

          samples.each { |s| add(**s) }
        end

        ##
        # Adds a calibration sample
        #
        # @param input [String] The input/prompt that was given
        # @param output [String] The output/response to evaluate
        # @param ground_truth [Boolean] Whether the output is actually correct
        # @param context [Hash] Optional additional context
        # @return [self]
        #
        # @example
        #   calibration.add(
        #     input: "Summarize this article",
        #     output: "This article discusses...",
        #     ground_truth: true,
        #     context: { domain: "news", difficulty: "medium" }
        #   )
        def add(input:, output:, ground_truth:, context: {})
          @samples << {
            input: input,
            output: output,
            ground_truth: ground_truth,
            context: context,
            added_at: Time.now.iso8601
          }
          self
        end

        ##
        # Returns positive samples (ground_truth = true)
        #
        # @return [Array<Hash>] Samples where ground_truth is true
        def positive_samples
          @samples.select { |s| s[:ground_truth] }
        end

        ##
        # Returns negative samples (ground_truth = false)
        #
        # @return [Array<Hash>] Samples where ground_truth is false
        def negative_samples
          @samples.reject { |s| s[:ground_truth] }
        end

        ##
        # Returns the count of positive samples (m1 in the paper)
        #
        # @return [Integer] Number of positive samples
        def m1
          positive_samples.size
        end

        ##
        # Returns the count of negative samples (m0 in the paper)
        #
        # @return [Integer] Number of negative samples
        def m0
          negative_samples.size
        end

        ##
        # Total number of samples
        #
        # @return [Integer] Total sample count
        def size
          @samples.size
        end

        ##
        # Checks if the calibration set is valid for use
        #
        # @param min_positive [Integer] Minimum positive samples required
        # @param min_negative [Integer] Minimum negative samples required
        # @return [Boolean] Whether the set meets minimum requirements
        def valid?(min_positive: 10, min_negative: 10)
          m1 >= min_positive && m0 >= min_negative
        end

        ##
        # Validates the calibration set, raising an error if invalid
        #
        # @param min_positive [Integer] Minimum positive samples required
        # @param min_negative [Integer] Minimum negative samples required
        # @raise [InsufficientCalibrationDataError] If requirements not met
        # @return [self]
        def validate!(min_positive: 10, min_negative: 10)
          unless valid?(min_positive: min_positive, min_negative: min_negative)
            raise InsufficientCalibrationDataError,
                  "Calibration set requires at least #{min_positive} positive and " \
                  "#{min_negative} negative samples. Got #{m1} positive and #{m0} negative."
          end
          self
        end

        ##
        # Splits the calibration set into train/test for cross-validation
        #
        # @param ratio [Float] Ratio of samples for training (0.0-1.0)
        # @param seed [Integer, nil] Random seed for reproducibility
        # @return [Array<CalibrationSet, CalibrationSet>] [train_set, test_set]
        def split(ratio: 0.8, seed: nil)
          rng = seed ? Random.new(seed) : Random.new
          shuffled = @samples.shuffle(random: rng)

          split_index = (shuffled.size * ratio).round
          train_samples = shuffled[0...split_index]
          test_samples = shuffled[split_index..]

          [
            CalibrationSet.new(samples: train_samples, metadata: @metadata.merge(split: :train)),
            CalibrationSet.new(samples: test_samples, metadata: @metadata.merge(split: :test))
          ]
        end

        ##
        # Stratified split maintaining positive/negative ratio
        #
        # @param ratio [Float] Ratio of samples for training (0.0-1.0)
        # @param seed [Integer, nil] Random seed for reproducibility
        # @return [Array<CalibrationSet, CalibrationSet>] [train_set, test_set]
        def stratified_split(ratio: 0.8, seed: nil)
          rng = seed ? Random.new(seed) : Random.new

          pos_shuffled = positive_samples.shuffle(random: rng)
          neg_shuffled = negative_samples.shuffle(random: rng)

          pos_split = (pos_shuffled.size * ratio).round
          neg_split = (neg_shuffled.size * ratio).round

          train_samples = pos_shuffled[0...pos_split] + neg_shuffled[0...neg_split]
          test_samples = pos_shuffled[pos_split..] + neg_shuffled[neg_split..]

          [
            CalibrationSet.new(samples: train_samples, metadata: @metadata.merge(split: :train)),
            CalibrationSet.new(samples: test_samples, metadata: @metadata.merge(split: :test))
          ]
        end

        ##
        # Filters samples by context attributes
        #
        # @param criteria [Hash] Key-value pairs to match in context
        # @return [CalibrationSet] Filtered calibration set
        #
        # @example Filter by domain
        #   medical_set = calibration.filter(domain: "medical")
        def filter(**criteria)
          filtered = @samples.select do |sample|
            criteria.all? { |k, v| sample[:context][k] == v }
          end

          CalibrationSet.new(
            samples: filtered,
            metadata: @metadata.merge(filtered_by: criteria)
          )
        end

        ##
        # Serializes the calibration set to JSON
        #
        # @return [String] JSON representation
        def to_json(*args)
          {
            metadata: @metadata,
            samples: @samples
          }.to_json(*args)
        end

        ##
        # Serializes to a hash
        #
        # @return [Hash] Hash representation
        def to_h
          {
            metadata: @metadata,
            samples: @samples
          }
        end

        ##
        # Loads a calibration set from JSON string
        #
        # @param json_string [String] JSON data
        # @return [CalibrationSet] Loaded calibration set
        def self.from_json(json_string)
          data = JSON.parse(json_string, symbolize_names: true)
          new(
            samples: data[:samples] || [],
            metadata: data[:metadata] || {}
          )
        end

        ##
        # Loads a calibration set from a JSON file
        #
        # @param file_path [String] Path to JSON file
        # @return [CalibrationSet] Loaded calibration set
        def self.load(file_path)
          from_json(File.read(file_path))
        end

        ##
        # Saves the calibration set to a JSON file
        #
        # @param file_path [String] Path to save to
        # @return [self]
        def save(file_path)
          File.write(file_path, JSON.pretty_generate(to_h))
          self
        end

        ##
        # Merges multiple calibration sets
        #
        # @param sets [Array<CalibrationSet>] Sets to merge
        # @return [CalibrationSet] Merged set
        def self.merge(*sets)
          all_samples = sets.flat_map(&:samples)
          new(
            samples: all_samples,
            metadata: { merged_from: sets.size, merged_at: Time.now.iso8601 }
          )
        end

        ##
        # Returns statistics about the calibration set
        #
        # @return [Hash] Statistics including counts and ratios
        def statistics
          {
            total_samples: size,
            positive_samples: m1,
            negative_samples: m0,
            positive_ratio: size.positive? ? m1.to_f / size : 0.0,
            negative_ratio: size.positive? ? m0.to_f / size : 0.0,
            balance_ratio: m0.positive? ? m1.to_f / m0 : Float::INFINITY
          }
        end
      end

      ##
      # Error raised when calibration data is insufficient
      class InsufficientCalibrationDataError < StandardError; end
    end
  end
end
