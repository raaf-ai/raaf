# frozen_string_literal: true

require "spec_helper"
require "raaf/perplexity/common"

RSpec.describe RAAF::Perplexity::Common do
  describe "SUPPORTED_MODELS" do
    it "includes all Perplexity models" do
      expect(described_class::SUPPORTED_MODELS).to contain_exactly(
        "sonar",
        "sonar-pro",
        "sonar-reasoning",
        "sonar-reasoning-pro",
        "sonar-deep-research"
      )
    end

    it "is frozen" do
      expect(described_class::SUPPORTED_MODELS).to be_frozen
    end
  end

  describe "SCHEMA_SUPPORTED_MODELS" do
    it "includes only models with JSON schema support" do
      expect(described_class::SCHEMA_SUPPORTED_MODELS).to contain_exactly(
        "sonar-pro",
        "sonar-reasoning-pro"
      )
    end

    it "is frozen" do
      expect(described_class::SCHEMA_SUPPORTED_MODELS).to be_frozen
    end
  end

  describe "RECENCY_FILTERS" do
    it "includes all valid recency filters" do
      expect(described_class::RECENCY_FILTERS).to contain_exactly(
        "hour",
        "day",
        "week",
        "month",
        "year"
      )
    end

    it "is frozen" do
      expect(described_class::RECENCY_FILTERS).to be_frozen
    end
  end

  describe ".validate_model" do
    context "with valid models" do
      it "does not raise error for sonar" do
        expect { described_class.validate_model("sonar") }.not_to raise_error
      end

      it "does not raise error for sonar-pro" do
        expect { described_class.validate_model("sonar-pro") }.not_to raise_error
      end

      it "does not raise error for sonar-reasoning" do
        expect { described_class.validate_model("sonar-reasoning") }.not_to raise_error
      end

      it "does not raise error for sonar-reasoning-pro" do
        expect { described_class.validate_model("sonar-reasoning-pro") }.not_to raise_error
      end

      it "does not raise error for sonar-deep-research" do
        expect { described_class.validate_model("sonar-deep-research") }.not_to raise_error
      end
    end

    context "with invalid models" do
      it "raises ArgumentError for unsupported model" do
        expect { described_class.validate_model("gpt-4o") }
          .to raise_error(ArgumentError, /not supported/)
      end

      it "includes supported models in error message" do
        expect { described_class.validate_model("invalid") }
          .to raise_error(ArgumentError, /sonar, sonar-pro/)
      end

      it "includes invalid model name in error message" do
        expect { described_class.validate_model("claude-3") }
          .to raise_error(ArgumentError, /claude-3/)
      end
    end
  end

  describe ".validate_schema_support" do
    context "with schema-supported models" do
      it "does not raise error for sonar-pro" do
        expect { described_class.validate_schema_support("sonar-pro") }.not_to raise_error
      end

      it "does not raise error for sonar-reasoning-pro" do
        expect { described_class.validate_schema_support("sonar-reasoning-pro") }.not_to raise_error
      end
    end

    context "with non-schema models" do
      it "raises ArgumentError for sonar" do
        expect { described_class.validate_schema_support("sonar") }
          .to raise_error(ArgumentError, /only supported on sonar-pro, sonar-reasoning-pro/)
      end

      it "raises ArgumentError for sonar-reasoning" do
        expect { described_class.validate_schema_support("sonar-reasoning") }
          .to raise_error(ArgumentError, /only supported on sonar-pro, sonar-reasoning-pro/)
      end

      it "raises ArgumentError for sonar-deep-research" do
        expect { described_class.validate_schema_support("sonar-deep-research") }
          .to raise_error(ArgumentError, /only supported on sonar-pro, sonar-reasoning-pro/)
      end

      it "includes current model in error message" do
        expect { described_class.validate_schema_support("sonar") }
          .to raise_error(ArgumentError, /Current model: sonar/)
      end
    end
  end

  describe ".validate_recency_filter" do
    context "with valid filters" do
      it "does not raise error for hour" do
        expect { described_class.validate_recency_filter("hour") }.not_to raise_error
      end

      it "does not raise error for day" do
        expect { described_class.validate_recency_filter("day") }.not_to raise_error
      end

      it "does not raise error for week" do
        expect { described_class.validate_recency_filter("week") }.not_to raise_error
      end

      it "does not raise error for month" do
        expect { described_class.validate_recency_filter("month") }.not_to raise_error
      end

      it "does not raise error for year" do
        expect { described_class.validate_recency_filter("year") }.not_to raise_error
      end

      it "does not raise error for nil" do
        expect { described_class.validate_recency_filter(nil) }.not_to raise_error
      end
    end

    context "with invalid filters" do
      it "raises ArgumentError for invalid filter" do
        expect { described_class.validate_recency_filter("minute") }
          .to raise_error(ArgumentError, /Invalid recency filter/)
      end

      it "includes invalid filter in error message" do
        expect { described_class.validate_recency_filter("decade") }
          .to raise_error(ArgumentError, /decade/)
      end

      it "includes supported filters in error message" do
        expect { described_class.validate_recency_filter("invalid") }
          .to raise_error(ArgumentError, /hour, day, week, month, year/)
      end
    end
  end
end
