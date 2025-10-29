# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Continuation::Logging do
  # These tests verify the logging module works without actual Rails setup
  # The module gracefully handles missing Rails logger with fallback to puts

  describe ".log_continuation_start" do
    it "creates a continuation start message with attempt and format" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_continuation_start(1, :csv)
      end
      expect(output).to include("🔄 Continuation attempt 1")
      expect(output).to include("format: csv")
    end

    it "handles different formats" do
      [:csv, :markdown, :json, :auto].each do |format|
        output = capture_stdout do
          RAAF::Continuation::Logging.log_continuation_start(1, format)
        end
        expect(output).to include(format.to_s)
      end
    end

    it "handles different attempt numbers" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_continuation_start(5, :json)
      end
      expect(output).to include("attempt 5")
    end
  end

  describe ".log_continuation_complete" do
    it "creates a completion message with attempt count and tokens" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_continuation_complete(3, 4500)
      end
      expect(output).to include("✅ Continuation complete")
      expect(output).to include("3 attempts")
      expect(output).to include("4500")
    end

    it "handles single attempt" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_continuation_complete(1, 1000)
      end
      expect(output).to include("1 attempts")
    end

    it "handles zero tokens" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_continuation_complete(2, 0)
      end
      expect(output).to include("0")
    end
  end

  describe ".log_finish_reason" do
    it "logs normal completion for stop" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("stop")
      end
      expect(output).to include("completed normally")
    end

    it "logs truncation warning for length" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("length")
      end
      expect(output).to include("truncated")
    end

    it "logs content filter warning" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("content_filter")
      end
      expect(output).to include("filtered")
    end

    it "logs tool calls info" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("tool_calls")
      end
      expect(output).to include("tool calls")
    end

    it "logs incomplete warning" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("incomplete")
      end
      expect(output).to include("incomplete")
    end

    it "logs error" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("error")
      end
      expect(output).to include("error")
    end

    it "logs unknown reason with fallback" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_finish_reason("unknown_reason")
      end
      expect(output).to include("unknown_reason")
    end
  end

  describe ".log_warning" do
    it "logs warning messages" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_warning("Too many attempts")
      end
      expect(output).to include("⚠️")
      expect(output).to include("Too many attempts")
    end
  end

  describe ".log_error" do
    it "logs error messages without exception" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_error("Continuation failed")
      end
      expect(output).to include("❌")
      expect(output).to include("Continuation failed")
    end

    it "logs error messages with exception" do
      error = StandardError.new("API timeout")
      output = capture_stdout do
        RAAF::Continuation::Logging.log_error("Continuation failed", error)
      end
      expect(output).to include("API timeout")
    end
  end

  describe ".log_metadata" do
    it "logs metadata with multiple fields" do
      metadata = { attempt: 1, format: :csv, tokens: 1250, duration_ms: 45 }
      output = capture_stdout do
        RAAF::Continuation::Logging.log_metadata(metadata)
      end
      expect(output).to include("📊")
      expect(output).to include("Continuation metadata")
    end

    it "handles empty metadata" do
      output = capture_stdout do
        RAAF::Continuation::Logging.log_metadata({})
      end
      expect(output).to include("📊")
    end
  end

  private

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
