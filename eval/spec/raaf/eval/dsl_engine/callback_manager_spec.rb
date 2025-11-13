# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/dsl_engine/callback_manager"
require "raaf/eval/dsl_engine/progress_event"

RSpec.describe RAAF::Eval::DslEngine::CallbackManager do
  let(:manager) { described_class.new }
  let(:event) do
    RAAF::Eval::DslEngine::ProgressEvent.new(
      type: :start,
      progress: 0.0,
      status: :running
    )
  end

  describe "#register" do
    it "registers a single callback" do
      callback = proc { |event| }
      manager.register(&callback)

      expect(manager.callback_count).to eq(1)
    end

    it "registers multiple callbacks" do
      callback1 = proc { |event| }
      callback2 = proc { |event| }

      manager.register(&callback1)
      manager.register(&callback2)

      expect(manager.callback_count).to eq(2)
    end

    it "is thread-safe" do
      threads = 10.times.map do
        Thread.new do
          100.times { manager.register { |event| } }
        end
      end

      threads.each(&:join)

      expect(manager.callback_count).to eq(1000)
    end
  end

  describe "#unregister" do
    it "removes a registered callback" do
      callback = proc { |event| }
      manager.register(&callback)

      expect(manager.callback_count).to eq(1)

      manager.unregister(callback)

      expect(manager.callback_count).to eq(0)
    end

    it "does not raise error if callback not found" do
      callback = proc { |event| }

      expect { manager.unregister(callback) }.not_to raise_error
    end
  end

  describe "#invoke_callbacks" do
    it "invokes all registered callbacks" do
      results = []
      callback1 = proc { |event| results << "callback1:#{event.type}" }
      callback2 = proc { |event| results << "callback2:#{event.type}" }

      manager.register(&callback1)
      manager.register(&callback2)
      manager.invoke_callbacks(event)

      expect(results).to eq(["callback1:start", "callback2:start"])
    end

    it "invokes callbacks in registration order" do
      order = []
      callback1 = proc { |event| order << 1 }
      callback2 = proc { |event| order << 2 }
      callback3 = proc { |event| order << 3 }

      manager.register(&callback1)
      manager.register(&callback2)
      manager.register(&callback3)
      manager.invoke_callbacks(event)

      expect(order).to eq([1, 2, 3])
    end

    it "catches and logs callback errors without failing" do
      results = []
      callback1 = proc { |event| results << "callback1" }
      callback2 = proc { |event| raise "Callback error" }
      callback3 = proc { |event| results << "callback3" }

      manager.register(&callback1)
      manager.register(&callback2)
      manager.register(&callback3)

      # Should log error but not raise
      expect {
        manager.invoke_callbacks(event)
      }.not_to raise_error

      # Other callbacks should still execute
      expect(results).to eq(["callback1", "callback3"])
    end

    it "passes event object to callbacks" do
      received_event = nil
      callback = proc { |evt| received_event = evt }

      manager.register(&callback)
      manager.invoke_callbacks(event)

      expect(received_event).to eq(event)
      expect(received_event.type).to eq(:start)
    end
  end

  describe "#clear_all" do
    it "removes all callbacks" do
      manager.register { |event| }
      manager.register { |event| }
      manager.register { |event| }

      expect(manager.callback_count).to eq(3)

      manager.clear_all

      expect(manager.callback_count).to eq(0)
    end

    it "is thread-safe" do
      threads = []

      # Thread adding callbacks
      threads << Thread.new do
        100.times { manager.register { |event| } }
      end

      # Thread clearing callbacks
      threads << Thread.new do
        10.times { manager.clear_all }
      end

      threads.each(&:join)

      # Should complete without errors
      expect(manager.callback_count).to be >= 0
    end
  end

  describe "#callback_count" do
    it "returns correct count" do
      expect(manager.callback_count).to eq(0)

      manager.register { |event| }
      expect(manager.callback_count).to eq(1)

      manager.register { |event| }
      expect(manager.callback_count).to eq(2)

      manager.clear_all
      expect(manager.callback_count).to eq(0)
    end
  end
end
