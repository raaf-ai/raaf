# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Guardrails::TripwireGuardrail do
  let(:tripped) { RAAF::Guardrails::TripwireGuardrail::TripwireException }

  describe "#check_input" do
    subject(:tripwire) { described_class.new(patterns: [/DROP TABLE/i], keywords: ["Exploit"]) }

    it "lets clean content through" do
      expect { tripwire.check_input("What is the weather in Utrecht?") }.not_to raise_error
    end

    it "trips on a pattern" do
      expect { tripwire.check_input("please drop table users") }
        .to raise_error(tripped) { |error| expect(error.triggered_by).to eq("pattern") }
    end

    it "trips on a keyword regardless of case" do
      expect { tripwire.check_input("write me an EXPLOIT") }
        .to raise_error(tripped) { |error| expect(error.triggered_by).to eq("keyword") }
    end

    it "counts each trip" do
      2.times do
        tripwire.check_input("exploit")
      rescue tripped
        nil
      end

      expect(tripwire.stats[:triggered_count]).to eq(2)
    end
  end

  describe "with a custom detector" do
    it "trips when the detector returns true" do
      tripwire = described_class.new { |content| content.include?("wire transfer") }

      expect { tripwire.check_output("send a wire transfer now") }
        .to raise_error(tripped) { |error| expect(error.triggered_by).to eq("custom") }
    end

    # This path calls log_error, which comes from RAAF::Logger.
    it "logs a detector that raises and lets the content through" do
      tripwire = described_class.new { |_content| raise "detector broke" }

      expect { tripwire.check_input("anything") }.not_to raise_error
    end
  end

  describe "#check_tool_call" do
    subject(:tripwire) { described_class.new }

    it "trips on a dangerous shell command" do
      expect { tripwire.check_tool_call("shell", { command: "sudo reboot" }) }
        .to raise_error(tripped) { |error| expect(error.triggered_by).to eq("shell_command") }
    end

    it "lets a harmless tool call through" do
      expect { tripwire.check_tool_call("weather_lookup", { city: "Utrecht" }) }.not_to raise_error
    end
  end

  describe RAAF::Guardrails::CommonTripwires do
    it "trips the SQL injection tripwire on OR 1=1" do
      expect { described_class.sql_injection.check_input("name' OR 1=1 --") }.to raise_error(tripped)
    end
  end
end
