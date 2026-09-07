# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::TimeRange do
  # The concern is a controller mixin, and everything in it is private. A bare
  # host exercises the precedence rules without a routing stack: what matters
  # here is which of three sources wins, not how a page renders.
  let(:host_class) do
    Class.new do
      include RAAF::Rails::TimeRange

      attr_reader :params, :session

      def initialize(params: {}, session: {})
        @params = params
        @session = session
      end

      # The rules under test are private; reach them deliberately.
      public :current_range, :range_duration
    end
  end

  def screen(params: {}, session: {})
    host_class.new(params: params, session: session)
  end

  describe "with nothing chosen" do
    it "opens on the screen's default" do
      expect(screen.current_range).to eq("24h")
    end

    it "honours a screen that opens on a different window" do
      wider = Class.new(host_class) do
        private

        def default_range
          "7d"
        end
      end

      expect(wider.new.current_range).to eq("7d")
    end
  end

  describe "with a range in the URL" do
    it "uses it" do
      expect(screen(params: { range: "7d" }).current_range).to eq("7d")
    end

    it "remembers it for later screens" do
      session = {}
      screen(params: { range: "7d" }, session: session).current_range

      expect(session["raaf_range"]).to eq("7d")
    end

    # The range arrives from a URL anyone can edit.
    it "ignores a range it does not offer" do
      expect(screen(params: { range: "all-time" }).current_range).to eq("24h")
    end

    it "does not let a range it does not offer evict a remembered one" do
      session = { "raaf_range" => "7d" }

      expect(screen(params: { range: "all-time" }, session: session).current_range).to eq("7d")
      expect(session["raaf_range"]).to eq("7d")
    end
  end

  describe "with a range remembered from an earlier screen" do
    it "uses it when the URL says nothing" do
      expect(screen(session: { "raaf_range" => "30d" }).current_range).to eq("30d")
    end

    # Otherwise a shared link would not show what it says.
    it "yields to an explicit range in the URL" do
      expect(screen(params: { range: "1h" }, session: { "raaf_range" => "30d" }).current_range)
        .to eq("1h")
    end

    # The wider window is a starting point, not an instruction. Once the reader
    # has said which window they want, that is the question they are asking on
    # every screen.
    it "beats a screen's own default" do
      wider = Class.new(host_class) do
        private

        def default_range
          "7d"
        end
      end

      expect(wider.new(session: { "raaf_range" => "1h" }).current_range).to eq("1h")
    end

    # Written by an older console, or by hand.
    it "ignores a remembered value it does not offer" do
      expect(screen(session: { "raaf_range" => "all-time" }).current_range).to eq("24h")
    end
  end

  describe "without a session" do
    # A host can mount the engine with sessions disabled. The range stops being
    # sticky; nothing else changes, and nothing raises.
    let(:sessionless) do
      Class.new do
        include RAAF::Rails::TimeRange

        attr_reader :params

        def initialize(params: {})
          @params = params
        end

        public :current_range
      end
    end

    it "still answers with the URL's range" do
      expect(sessionless.new(params: { range: "7d" }).current_range).to eq("7d")
    end

    it "still answers with the default" do
      expect(sessionless.new.current_range).to eq("24h")
    end
  end

  describe "#range_duration" do
    it "translates the chosen range into a window" do
      expect(screen(params: { range: "7d" }).range_duration).to eq(7.days)
    end
  end
end
