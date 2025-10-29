# frozen_string_literal: true

module RAAF
  module Continuation
    # Load continuation module components
    autoload :Config, "raaf/continuation/config"
    autoload :FormatDetector, "raaf/continuation/format_detector"
    autoload :MergerFactory, "raaf/continuation/merger_factory"
    autoload :MergeError, "raaf/continuation/errors"
    autoload :TruncationError, "raaf/continuation/errors"
    autoload :PartialResultBuilder, "raaf/continuation/partial_result_builder"
    autoload :ErrorHandler, "raaf/continuation/error_handler"
    autoload :Logging, "raaf/continuation/logging"
    autoload :CostCalculator, "raaf/continuation/cost_calculator"

    module Mergers
      autoload :BaseMerger, "raaf/continuation/mergers/base_merger"
      autoload :CSVMerger, "raaf/continuation/mergers/csv_merger"
      autoload :MarkdownMerger, "raaf/continuation/mergers/markdown_merger"
      autoload :JSONMerger, "raaf/continuation/mergers/json_merger"
    end
  end
end
