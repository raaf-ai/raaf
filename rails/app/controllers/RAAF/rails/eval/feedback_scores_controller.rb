# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for managing feedback scores
      class FeedbackScoresController < BaseController
        FeedbackScore = RAAF::Eval::Models::FeedbackScore

        # GET /raaf/eval/feedback_scores
        def index
          @scores = FeedbackScore.recent
          @scores = @scores.for_span(params[:span_id]) if params[:span_id].present?
          @scores = @scores.for_trace(params[:trace_id]) if params[:trace_id].present?
          @scores = @scores.for_name(params[:name]) if params[:name].present?

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::FeedbackScoreList.new(
                scores: @scores.limit(100),
                stats: FeedbackScore.score_statistics,
                distribution: FeedbackScore.category_distribution,
                definitions: score_definitions
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(
                title: "Feedback scores", crumb: "Evaluate", current: :feedback
              ) { render component }
              render layout
            end
            format.json { render json: @scores.limit(100) }
          end
        end

        # GET /raaf/eval/feedback_scores/:id
        def show
          @score = FeedbackScore.find(params[:id])
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::FeedbackScoreShow.new(score: @score)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Feedback Score") { render component }
              render layout
            end
            format.json { render json: @score }
          end
        end

        # POST /raaf/eval/feedback_scores
        def create
          @score = FeedbackScore.new(feedback_score_params)
          if @score.save
            respond_to do |format|
              format.html { redirect_to eval_feedback_scores_path, notice: "Score recorded." }
              format.json { render json: @score, status: :created }
            end
          else
            respond_to do |format|
              format.html { redirect_to eval_feedback_scores_path, alert: @score.errors.full_messages.join(", ") }
              format.json { render json: { errors: @score.errors }, status: :unprocessable_content }
            end
          end
        end

        # POST /raaf/eval/feedback_scores/score_span
        def score_span
          scores = FeedbackScore.score_span(
            span_id: params[:span_id],
            scores: params[:scores].to_unsafe_h,
            scored_by: params[:scored_by],
            source: params[:source] || "ui"
          )
          respond_to do |format|
            format.html do
              redirect_to eval_feedback_scores_path(span_id: params[:span_id]),
                          notice: "#{scores.size} scores recorded."
            end
            format.json { render json: scores, status: :created }
          end
        end

        # POST /raaf/eval/feedback_scores/score_trace
        def score_trace
          scores = FeedbackScore.score_trace(
            trace_id: params[:trace_id],
            scores: params[:scores].to_unsafe_h,
            scored_by: params[:scored_by],
            source: params[:source] || "ui"
          )
          respond_to do |format|
            format.html do
              redirect_to eval_feedback_scores_path(trace_id: params[:trace_id]),
                          notice: "#{scores.size} scores recorded."
            end
            format.json { render json: scores, status: :created }
          end
        end

        # GET /raaf/eval/feedback_scores/statistics
        def statistics
          stats = FeedbackScore.score_statistics
          distribution = FeedbackScore.category_distribution

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::FeedbackStatistics.new(stats: stats, distribution: distribution)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Feedback Statistics") { render component }
              render layout
            end
            format.json { render json: { statistics: stats, distribution: distribution } }
          end
        end

        # DELETE /raaf/eval/feedback_scores/:id
        def destroy
          @score = FeedbackScore.find(params[:id])
          @score.destroy
          redirect_to eval_feedback_scores_path, notice: "Score deleted."
        end

        private

        # What each score name is, derived from the scores themselves — the
        # schema has no definition table. A name is numerical or categorical
        # by which column its scores fill, and its range is the span those
        # scores cover, so the list describes what has actually been recorded
        # rather than what someone once intended.
        def score_definitions
          numerical = FeedbackScore.numerical.group(:name)
          categorical = FeedbackScore.categorical.group(:name)

          rows = numerical_definitions(numerical) + categorical_definitions(categorical)
          rows.sort_by { |definition| -definition[:count] }
        end

        def numerical_definitions(scope)
          counts = scope.count
          minimums = scope.minimum(:value)
          maximums = scope.maximum(:value)

          counts.map do |name, count|
            { name: name, type: "numerical", count: count,
              range: "#{format('%.2f', minimums[name].to_f)} – #{format('%.2f', maximums[name].to_f)}" }
          end
        end

        def categorical_definitions(scope)
          categories = scope.distinct.count(:category_value)

          scope.count.map do |name, count|
            { name: name, type: "categorical", count: count,
              range: "#{categories[name].to_i} cats" }
          end
        end

        def feedback_score_params
          params.require(:feedback_score).permit(:name, :source, :span_id, :trace_id, :value, :category_value, :reason,
                                                 :scored_by, metadata: {})
        end
      end
    end
  end
end
