# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # What one check has been scoring lately, so a single verdict can be read
      # against the ones around it.
      #
      # The Result screen asked "whether this verdict is the odd one out" and
      # answered it by listing recent results of the same *policy*. That is the
      # wrong set twice over. A policy that has graded one span has nothing to
      # show, so the panel sat empty on exactly the screens it was built for.
      # And a policy runs several checks against different fields, so even when
      # it does have neighbours they answer different questions on different
      # scales — a relevance score beside a latency score is two numbers that
      # cannot be the odd one out of each other.
      #
      # The comparable set is the same check: one evaluator, one field, across
      # the spans it has graded. That is what makes a 1.00 readable, and it is
      # also the only way to see the thing a single result can never show —
      # that a check has returned the same number every time it has ever run,
      # and is therefore telling nobody anything.
      #
      class CheckHistory
        # Rows the panel lists. Long enough to see a pattern, short enough to
        # sit in a sidebar.
        LIMIT = 6

        # How far back the figures are drawn from. Long enough that a nightly
        # policy has run more than once.
        WINDOW = 30.days

        # Scores this far apart are the same answer twice. A check whose whole
        # range is narrower than this has not distinguished anything.
        FLAT_RANGE = 0.005

        # Below this there is not enough history to call a check flat: one run
        # is not a pattern.
        MIN_FOR_PATTERN = 3

        EvaluationResult = RAAF::Eval::Models::ContinuousEvaluationResult

        # @param result [ContinuousEvaluationResult] the verdict being read
        # @param limit [Integer] rows to list
        # @param window [ActiveSupport::Duration] how far back to measure
        def initialize(result:, limit: LIMIT, window: WINDOW, now: Time.current)
          @result = result
          @limit = limit
          @window = window
          @now = now
        end

        ##
        # @return [String, nil] the field this check graded, which together
        #   with the evaluator names the check
        def field
          @field ||= @result.metadata&.dig("field_name").presence ||
                     @result.metadata&.dig(:field_name).presence ||
                     @result.details&.dig("field_name").presence
        end

        ##
        # What this check scored on each of the other spans, newest first.
        #
        # Other spans rather than other results: the same span re-graded is the
        # same question asked twice, and the screen lists those separately.
        #
        # @return [Array<ContinuousEvaluationResult>]
        def results
          @results ||= per_span(scope).order(created_at: :desc, id: :desc).limit(@limit).to_a
        end

        ##
        # One score per span this check has graded, this result included — it
        # is what the check made of its own span, and leaving it out would make
        # a run of identical verdicts look like it had variety.
        #
        # @return [Array<Float>]
        def scores
          @scores ||= begin
            others = per_span(scope).where.not(score: nil).limit(200).pluck(:score).map(&:to_f)
            (@result.score ? others + [@result.score.to_f] : others).sort
          end
        end

        ##
        # The last time this check ran before this one.
        #
        # @return [ContinuousEvaluationResult, nil]
        def previous
          return @previous if defined?(@previous)

          @previous = earlier.order(created_at: :desc, id: :desc).first
        end

        ##
        # What the check had been averaging before this run.
        #
        # Strictly before: an average this result is part of moves towards it,
        # so a verdict measured against it always looks closer to normal than
        # it is.
        #
        # @return [Float, nil]
        def average
          return @average if defined?(@average)

          values = earlier.where.not(score: nil).limit(200).pluck(:score).map(&:to_f)
          @average = values.empty? ? nil : values.sum / values.size
        end

        # @return [Float, nil] how far this verdict sits from the run before it
        def delta_vs_previous
          return nil if @result.score.nil? || previous&.score.nil?

          @result.score.to_f - previous.score.to_f
        end

        # @return [Float, nil] how far this verdict sits from the running mean
        def delta_vs_average
          return nil if @result.score.nil? || average.nil?

          @result.score.to_f - average
        end

        # @return [Integer] how many runs the average is taken over
        def earlier_count
          @earlier_count ||= earlier.where.not(score: nil).count
        end

        def count = scores.size

        def median
          return nil if scores.empty?

          middle = scores.size / 2
          scores.size.odd? ? scores[middle] : (scores[middle - 1] + scores[middle]) / 2.0
        end

        def low = scores.first
        def high = scores.last

        ##
        # Whether this check has ever answered two different things.
        #
        # The one fact a single result can never carry, and the one most worth
        # knowing: a check that has returned 1.00 on every span it has graded
        # is not passing, it is not measuring.
        #
        # @return [Boolean, nil] nil where there is too little history to say
        def flat?
          return nil if count < MIN_FOR_PATTERN

          (high - low) < FLAT_RANGE
        end

        ##
        # How many of the check's scores this one beats, as a share.
        #
        # @return [Float, nil] nil where this result carries no score, or where
        #   the check has never varied and a rank would be meaningless
        def rank
          return nil if @result.score.nil? || count < MIN_FOR_PATTERN || flat?

          below = scores.count { |score| score < @result.score.to_f }
          below / (count - 1).to_f
        end

        ##
        # @return [Boolean] whether there is anything to compare against
        def any?
          results.any? || count > 1
        end

        ##
        # How many times this check has graded this span, this run included.
        #
        # A check pointed at one span and replayed has no history of how it
        # scores, which is why none of the figures above count its replays.
        # It has said something else worth a line, though: whether it gives
        # the same input the same answer twice. A screen that answers "nothing
        # yet" to the eighth run of a check reads as broken.
        #
        # @return [Integer]
        def repeat_count
          @repeat_count ||= repeats.count + 1
        end

        ##
        # @return [Boolean, nil] whether every one of those runs agreed; nil
        #   where fewer than two of them carried a score to agree on
        def repeats_agree?
          values = (repeats.where.not(score: nil).limit(200).pluck(:score) +
                    [@result.score]).compact.map(&:to_f)
          return nil if values.size < 2

          (values.max - values.min) < FLAT_RANGE
        end

        private

        # The other times this check has graded this span. The same question
        # asked again, which is why it is counted apart from the spans.
        def repeats
          return EvaluationResult.none if @result.evaluator_name.blank? || field.blank?

          EvaluationResult
            .where(evaluator_name: @result.evaluator_name, span_id: @result.span_id)
            .where.not(id: @result.id)
            .where(created_at: @now - @window..)
            .where(
              "COALESCE(metadata->>'field_name', details->>'field_name') = ?",
              field.to_s
            )
        end

        # Every run of this check on another span inside the window.
        #
        # The same evaluator on the same field: a result whose field cannot be
        # read is not comparable to anything, and matching on the evaluator
        # alone would put a latency verdict beside a relevance one.
        #
        # Another span rather than this one: the results for this span sit in
        # their own card on the same screen, and this result stands for its own
        # span in every figure below.
        def scope
          return EvaluationResult.none if @result.evaluator_name.blank? || field.blank?

          EvaluationResult
            .where(evaluator_name: @result.evaluator_name)
            .where.not(span_id: @result.span_id)
            .where(created_at: @now - @window..)
            .where(
              "COALESCE(metadata->>'field_name', details->>'field_name') = ?",
              field.to_s
            )
        end

        # One row per span, the latest verdict standing for the span.
        #
        # A span graded four times is one thing the check has scored, not four.
        # Counting each re-run separately had a card headed "how this check
        # usually scores" report four scores, a three-run average and a
        # never-varies verdict off a single span, above a list holding nothing
        # — every figure drawn from re-runs the listing itself leaves out.
        def per_span(relation)
          EvaluationResult.from(
            relation
              .select(Arel.sql("DISTINCT ON (span_id) #{EvaluationResult.table_name}.*"))
              .reorder(Arel.sql("span_id, created_at DESC, id DESC")),
            EvaluationResult.table_name
          )
        end

        # The runs before this one, which is what "previously" can mean without
        # the answer moving as the window slides. A span is represented by the
        # last verdict it had before this result, not by one written since.
        def earlier
          return per_span(scope) if @result.created_at.nil?

          per_span(scope.where(created_at: ...@result.created_at))
        end
      end
    end
  end
end
