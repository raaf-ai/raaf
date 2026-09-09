# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for managing feedback scores
      class FeedbackScoresController < BaseController
        Definition = RAAF::Eval::Models::FeedbackScoreDefinition

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
              render_in_layout component, title: "Feedback scores", crumb: "Evaluate", current: :feedback
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
              render_in_layout component, title: "Feedback Score"
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

        # GET /raaf/eval/feedback_scores/statistics.json
        #
        # JSON only. The HTML branch rendered the same five figures and the
        # same category distribution the Feedback list already carries, in the
        # light theme, and nothing had linked it since those moved onto the
        # list.
        def statistics
          render json: { statistics: FeedbackScore.score_statistics,
                         distribution: FeedbackScore.category_distribution }
        end

        # DELETE /raaf/eval/feedback_scores/:id
        def destroy
          @score = FeedbackScore.find(params[:id])
          @score.destroy
          redirect_to eval_feedback_scores_path, notice: "Score deleted."
        end

        private

        # What each score name is, read from the definitions table.
        #
        # This used to be derived from the scores themselves, under a comment
        # saying the schema had no definition table. It has one:
        # FeedbackScoreDefinition, with a full CRUD controller answering JSON.
        # Inferring instead meant a definition configured but never scored was
        # invisible, and one declared 1–5 showed as 2–4 until something extreme
        # was recorded — the card described what had happened rather than what
        # was agreed.
        #
        # A name that has been scored without a definition still gets a row,
        # because dropping it would hide real data behind a missing record.
        # Those rows say so, so the two kinds are not read as one.
        def score_definitions
          counts = FeedbackScore.group(:name).count
          declared = Definition.order(:name).map { |definition| declared_row(definition, counts) }

          declared + undeclared_rows(counts, declared.pluck(:name))
        end

        def declared_row(definition, counts)
          { name: definition.name, type: definition.score_type,
            count: counts.fetch(definition.name, 0),
            range: declared_range(definition), declared: true }
        end

        # The range the definition declares, not the one its scores happen to
        # cover.
        def declared_range(definition)
          if definition.numerical?
            "#{format('%.2f', definition.min_value.to_f)} – #{format('%.2f', definition.max_value.to_f)}"
          else
            "#{Array(definition.categories).size} cats"
          end
        end

        # Scored under a name nothing declares. Described from the scores,
        # since there is nothing else to describe it from.
        def undeclared_rows(counts, declared_names)
          (counts.keys - declared_names).map do |name|
            scope = FeedbackScore.where(name: name)
            numerical = scope.numerical.exists?

            { name: name, type: numerical ? "numerical" : "categorical",
              count: counts[name], declared: false,
              range: observed_range(scope, numerical) }
          end.sort_by { |row| -row[:count] }
        end

        def observed_range(scope, numerical)
          return "#{scope.distinct.count(:category_value)} cats" unless numerical

          "#{format('%.2f', scope.minimum(:value).to_f)} – #{format('%.2f', scope.maximum(:value).to_f)}"
        end

        def feedback_score_params
          params.require(:feedback_score).permit(:name, :source, :span_id, :trace_id, :value, :category_value, :reason,
                                                 :scored_by, metadata: {})
        end
      end
    end
  end
end
