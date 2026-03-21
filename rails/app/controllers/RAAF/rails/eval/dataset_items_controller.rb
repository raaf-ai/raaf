# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for dataset items
      class DatasetItemsController < BaseController
        before_action :set_dataset

        # GET /raaf/eval/datasets/:dataset_id/items
        def index
          @items = @dataset.dataset_items.recent
          respond_to do |format|
            format.json { render json: @items }
          end
        end

        # GET /raaf/eval/datasets/:dataset_id/items/:id
        def show
          @item = @dataset.dataset_items.find(params[:id])
          respond_to do |format|
            format.json { render json: @item }
          end
        end

        # POST /raaf/eval/datasets/:dataset_id/items
        def create
          item = @dataset.add_item(
            input: params[:item][:input].to_unsafe_h,
            expected_output: params[:item][:expected_output]&.to_unsafe_h || {},
            metadata: params[:item][:metadata]&.to_unsafe_h || {}
          )
          respond_to do |format|
            format.html { redirect_to eval_dataset_path(@dataset), notice: "Item added." }
            format.json { render json: item, status: :created }
          end
        end

        # POST /raaf/eval/datasets/:dataset_id/items/import_from_span
        def import_from_span
          span_data = fetch_span_data(params[:span_id])
          item = @dataset.add_item_from_span(span_data)
          respond_to do |format|
            format.html { redirect_to eval_dataset_path(@dataset), notice: "Item imported from span." }
            format.json { render json: item, status: :created }
          end
        end

        # DELETE /raaf/eval/datasets/:dataset_id/items/:id
        def destroy
          @item = @dataset.dataset_items.find(params[:id])
          @item.destroy
          @dataset.decrement!(:items_count)
          redirect_to eval_dataset_path(@dataset), notice: "Item removed."
        end

        private

        def set_dataset
          @dataset = RAAF::Eval::Models::Dataset.find(params[:dataset_id])
        end

        def fetch_span_data(span_id)
          if defined?(RAAF::Rails::Tracing::SpanRecord)
            span = RAAF::Rails::Tracing::SpanRecord.find_by!(span_id: span_id)
            span.attributes.symbolize_keys
          else
            { span_id: span_id }
          end
        end
      end
    end
  end
end
