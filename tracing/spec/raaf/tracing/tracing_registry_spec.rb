# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::TracingRegistry do
  # Mock tracer for testing
  let(:mock_tracer) { double("MockTracer") }
  let(:another_tracer) { double("AnotherTracer") }
  let(:process_tracer) { double("ProcessTracer") }

  before do
    # Clear any existing state before each test
    described_class.clear_all_contexts!
  end

  after do
    # Clean up after each test
    described_class.clear_all_contexts!
  end

  describe ".with_tracer" do
    context "with thread-local storage" do
      it "sets tracer in current thread context" do
        described_class.with_tracer(mock_tracer) do
          expect(described_class.current_tracer).to eq(mock_tracer)
        end
      end

      it "restores previous tracer after block execution" do
        expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)

        described_class.with_tracer(mock_tracer) do
          expect(described_class.current_tracer).to eq(mock_tracer)
        end

        expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
      end

      it "handles nested contexts with different tracers" do
        described_class.with_tracer(mock_tracer) do
          expect(described_class.current_tracer).to eq(mock_tracer)

          described_class.with_tracer(another_tracer) do
            expect(described_class.current_tracer).to eq(another_tracer)
          end

          expect(described_class.current_tracer).to eq(mock_tracer)
        end

        expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
      end

      it "properly restores context even when block raises exception" do
        expect {
          described_class.with_tracer(mock_tracer) do
            expect(described_class.current_tracer).to eq(mock_tracer)
            raise StandardError, "test error"
          end
        }.to raise_error(StandardError, "test error")

        expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
      end

      it "returns the result of the block" do
        result = described_class.with_tracer(mock_tracer) do
          "test result"
        end

        expect(result).to eq("test result")
      end
    end

    context "with fiber-local storage" do
      it "isolates tracers between fibers", :fiber_test do
        skip "Fiber-local storage not available in this Ruby version" unless fiber_storage_available?

        main_fiber_tracer = nil
        nested_fiber_tracer = nil
        main_thread = Thread.current

        described_class.with_tracer(mock_tracer) do
          main_fiber_tracer = described_class.current_tracer

          fiber = Fiber.new do
            described_class.with_tracer(another_tracer) do
              nested_fiber_tracer = described_class.current_tracer
            end
          end
          fiber.resume
        end

        expect(main_fiber_tracer).to eq(mock_tracer)
        expect(nested_fiber_tracer).to eq(another_tracer)
      end
    end
  end

  describe ".current_tracer" do
    context "priority hierarchy" do
      it "returns thread-local tracer when available" do
        described_class.set_process_tracer(process_tracer)
        Thread.current[:raaf_tracer] = mock_tracer

        expect(described_class.current_tracer).to eq(mock_tracer)
      ensure
        Thread.current[:raaf_tracer] = nil
        described_class.set_process_tracer(nil)
      end

      it "falls back to process-level tracer when no thread tracer" do
        described_class.set_process_tracer(process_tracer)
        expect(described_class.current_tracer).to eq(process_tracer)
      ensure
        described_class.set_process_tracer(nil)
      end

      it "returns NoOpTracer when no tracer is configured" do
        tracer = described_class.current_tracer
        expect(tracer).to be_a(RAAF::Tracing::NoOpTracer)
      end

      it "respects fiber-local tracer over thread tracer when in fiber" do
        skip "Fiber-local storage not available in this Ruby version" unless fiber_storage_available?

        Thread.current[:raaf_tracer] = mock_tracer

        fiber_result = nil
        fiber = Fiber.new do
          Fiber.current[:raaf_tracer] = another_tracer
          fiber_result = described_class.current_tracer
        end
        fiber.resume

        expect(fiber_result).to eq(another_tracer)
      ensure
        Thread.current[:raaf_tracer] = nil
      end
    end
  end

  describe ".set_process_tracer" do
    it "sets process-level default tracer" do
      described_class.set_process_tracer(process_tracer)
      expect(described_class.current_tracer).to eq(process_tracer)
    ensure
      described_class.set_process_tracer(nil)
    end

    it "allows process tracer to be cleared" do
      described_class.set_process_tracer(process_tracer)
      expect(described_class.current_tracer).to eq(process_tracer)

      described_class.set_process_tracer(nil)
      expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
    end
  end

  describe "thread safety" do
    it "isolates tracers between different threads" do
      thread1_tracer = nil
      thread2_tracer = nil
      barrier = Barrier.new(2)

      thread1 = Thread.new do
        described_class.with_tracer(mock_tracer) do
          barrier.wait # Synchronize threads
          sleep(0.01) # Give other thread time to set its tracer
          thread1_tracer = described_class.current_tracer
        end
      end

      thread2 = Thread.new do
        described_class.with_tracer(another_tracer) do
          barrier.wait # Synchronize threads
          sleep(0.01) # Give other thread time to set its tracer
          thread2_tracer = described_class.current_tracer
        end
      end

      thread1.join
      thread2.join

      expect(thread1_tracer).to eq(mock_tracer)
      expect(thread2_tracer).to eq(another_tracer)
    end
  end

  describe "memory management" do
    it "clears contexts when requested" do
      Thread.current[:raaf_tracer] = mock_tracer
      described_class.set_process_tracer(process_tracer)

      described_class.clear_all_contexts!

      expect(Thread.current[:raaf_tracer]).to be_nil
      expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
    end

    it "handles graceful cleanup in long-running processes" do
      # Simulate long-running process with many context switches
      100.times do |i|
        tracer = double("Tracer#{i}")
        described_class.with_tracer(tracer) do
          expect(described_class.current_tracer).to eq(tracer)
        end
      end

      # Should not accumulate memory from previous contexts
      expect(Thread.current[:raaf_tracer]).to be_nil
    end
  end

  describe "edge cases" do
    it "handles nil tracer gracefully" do
      described_class.with_tracer(nil) do
        expect(described_class.current_tracer).to be_a(RAAF::Tracing::NoOpTracer)
      end
    end

    it "handles tracer objects without expected interface" do
      invalid_tracer = "not a tracer"
      described_class.with_tracer(invalid_tracer) do
        expect(described_class.current_tracer).to eq(invalid_tracer)
      end
    end

    it "maintains context across yield boundaries" do
      def test_method(&block)
        described_class.with_tracer(another_tracer) do
          yield
        end
      end

      described_class.with_tracer(mock_tracer) do
        expect(described_class.current_tracer).to eq(mock_tracer)
        test_method do
          expect(described_class.current_tracer).to eq(another_tracer)
        end
        expect(described_class.current_tracer).to eq(mock_tracer)
      end
    end
  end

  describe "integration with existing RAAF patterns" do
    it "works with existing tracer detection patterns" do
      # Simulate existing RAAF code that checks for tracer availability
      expect(described_class.current_tracer).to respond_to(:class)

      described_class.with_tracer(mock_tracer) do
        tracer = described_class.current_tracer
        expect(tracer).not_to be_nil
        expect(tracer).to eq(mock_tracer)
      end
    end

    it "provides consistent interface for different tracer types" do
      [mock_tracer, another_tracer, nil].each do |tracer|
        described_class.with_tracer(tracer) do
          current = described_class.current_tracer
          expect(current).to respond_to(:class)
        end
      end
    end
  end
  # Helper method to check if fiber-local storage is available
  def fiber_storage_available?
    return false unless defined?(Fiber)

    # Test if Fiber supports []= assignment
    test_fiber = Fiber.new { Fiber.current[:test] = true }
    test_fiber.resume
    true
  rescue StandardError
    false
  end
end

# Simple barrier class for thread synchronization in tests
class Barrier
  def initialize(count)
    @count = count
    @waiting = 0
    @mutex = Mutex.new
    @condition = ConditionVariable.new
  end

  def wait
    @mutex.synchronize do
      @waiting += 1
      if @waiting == @count
        @condition.broadcast
      else
        @condition.wait(@mutex)
      end
    end
  end
end