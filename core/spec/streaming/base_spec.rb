# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/streaming/base"

RSpec.describe "RAAF Async Components" do
  describe RAAF::Async::Base do
    # Create a test class to include the module
    let(:test_class) do
      Class.new do
        include RAAF::Async::Base
      end
    end
    let(:test_instance) { test_class.new }

    describe "#async" do
      it "executes a block asynchronously" do
        result = test_instance.async { "async result" }
        expect(result).to be_a(Async::Task)
        expect(result.wait).to eq("async result")
      end

      it "can handle multiple async tasks" do
        task1 = test_instance.async { 1 + 1 }
        task2 = test_instance.async { 2 + 2 }

        expect(task1.wait).to eq(2)
        expect(task2.wait).to eq(4)
      end

      it "propagates exceptions from async blocks" do
        task = test_instance.async { raise StandardError, "test error" }

        expect { task.wait }.to raise_error(StandardError, "test error")
      end
    end

    describe "#await_all" do
      it "waits for multiple tasks to complete" do
        task1 = test_instance.async { "result1" }
        task2 = test_instance.async { "result2" }
        task3 = test_instance.async { "result3" }

        results_task = test_instance.await_all(task1, task2, task3)
        results = results_task.wait

        expect(results).to contain_exactly("result1", "result2", "result3")
      end

      it "handles empty task list" do
        results_task = test_instance.await_all
        results = results_task.wait

        expect(results).to eq([])
      end
    end

    describe "#async_http_client" do
      it "creates an HTTP client" do
        client = test_instance.async_http_client
        expect(client).to be_a(Async::HTTP::Client)
      end

      it "memoizes the HTTP client" do
        client1 = test_instance.async_http_client
        client2 = test_instance.async_http_client
        expect(client1).to be(client2)
      end

      it "uses OpenAI API endpoint" do
        client = test_instance.async_http_client
        expect(client.endpoint.to_s).to include("api.openai.com")
      end
    end

    describe "#async_sleep" do
      it "returns an async task that sleeps" do
        task = test_instance.async_sleep(0.01)
        expect(task).to be_a(Async::Task)

        start_time = Time.now
        task.wait
        elapsed = Time.now - start_time
        expect(elapsed).to be >= 0.005 # More lenient timing
      end
    end

    describe "#with_concurrency_limit" do
      it "creates tasks with concurrency limit" do
        task = test_instance.with_concurrency_limit(2) { "success" }
        expect(task).to be_a(Async::Task)
        expect(task.wait).to eq("success")
      end

      it "handles exceptions within concurrency limit" do
        task1 = test_instance.with_concurrency_limit(2) { "success" }
        task2 = test_instance.with_concurrency_limit(2) { raise StandardError, "failed" }

        expect(task1.wait).to eq("success")
        expect { task2.wait }.to raise_error(StandardError, "failed")
      end
    end

    describe "#make_async" do
      before do
        # Add a test method to our test instance
        test_instance.define_singleton_method(:test_method) do |arg1, arg2, keyword: nil|
          "#{arg1}_#{arg2}_#{keyword}"
        end
      end

      it "creates an async version of a method" do
        test_instance.make_async(:test_method)

        expect(test_instance).to respond_to(:test_method_async)

        task = test_instance.test_method_async("hello", "world", keyword: "test")
        expect(task).to be_a(Async::Task)
        expect(task.wait).to eq("hello_world_test")
      end

      it "preserves method arguments and keywords" do
        test_instance.make_async(:test_method)

        task = test_instance.test_method_async("arg1", "arg2", keyword: "kw")
        expect(task.wait).to eq("arg1_arg2_kw")
      end
    end

    describe "#in_async_context?" do
      it "returns false when not in async context" do
        expect(test_instance.in_async_context?).to be false
      end

      it "returns true when in async context" do
        result = nil

        Async do
          result = test_instance.in_async_context?
        end.wait

        expect(result).to be true
      end

      it "handles exceptions gracefully" do
        # Mock Task.current? to raise an exception
        allow(Async::Task).to receive(:current?).and_raise(StandardError, "mock error")

        expect(test_instance.in_async_context?).to be false
      end
    end

    describe "#ensure_async" do
      it "executes block directly when in async context" do
        result = nil

        Async do
          result = test_instance.ensure_async { "in_async" }
        end.wait

        expect(result).to eq("in_async")
      end

      it "wraps block in async when not in async context" do
        result = test_instance.ensure_async { "wrapped_async" }
        expect(result).to eq("wrapped_async")
      end

      it "returns values correctly from async wrapper" do
        result = test_instance.ensure_async { 42 }
        expect(result).to eq(42)
      end
    end
  end

  describe RAAF::Async::AsyncQueue do
    let(:queue) { described_class.new }

    describe "#initialize" do
      it "creates an empty queue" do
        expect(queue.empty?).to be true
        expect(queue.size).to eq(0)
      end

      it "accepts max_size parameter" do
        bounded_queue = described_class.new(5)
        expect(bounded_queue.empty?).to be true
        expect(bounded_queue.size).to eq(0)
      end
    end

    describe "#push and #pop" do
      it "can push and pop items synchronously" do
        queue.push("item1")
        queue.push("item2")

        expect(queue.size).to eq(2)
        expect(queue.empty?).to be false

        item1 = queue.pop
        item2 = queue.pop

        expect(item1).to eq("item1")
        expect(item2).to eq("item2")
        expect(queue.empty?).to be true
      end

      it "maintains FIFO order" do
        queue.push("first")
        queue.push("second")
        queue.push("third")

        items = []
        items << queue.pop
        items << queue.pop
        items << queue.pop

        expect(items).to eq(%w[first second third])
      end
    end

    describe "#size and #empty?" do
      it "reports correct size and empty status" do
        expect(queue.size).to eq(0)
        expect(queue.empty?).to be true

        queue.push("item1")
        expect(queue.size).to eq(1)
        expect(queue.empty?).to be false

        queue.push("item2")
        expect(queue.size).to eq(2)
        expect(queue.empty?).to be false

        queue.pop
        expect(queue.size).to eq(1)
        expect(queue.empty?).to be false

        queue.pop
        expect(queue.size).to eq(0)
        expect(queue.empty?).to be true
      end
    end

    describe "bounded queue" do
      let(:bounded_queue) { described_class.new(2) }

      it "respects size limit" do
        bounded_queue.push("item1")
        bounded_queue.push("item2")
        expect(bounded_queue.size).to eq(2)

        # Test that we can still pop from full queue
        popped = bounded_queue.pop
        expect(popped).to eq("item1")
        expect(bounded_queue.size).to eq(1)
      end
    end

    describe "error handling" do
      it "handles basic operations without errors" do
        expect { queue.push("test_item") }.not_to raise_error
        expect { queue.size }.not_to raise_error
        expect { queue.empty? }.not_to raise_error
        expect { queue.pop }.not_to raise_error
      end
    end

    describe "outside async context" do
      it "can operate outside async context" do
        # This tests the ensure_async wrapper
        queue.push("sync_item")
        expect(queue.size).to eq(1)

        popped = queue.pop
        expect(popped).to eq("sync_item")
        expect(queue.empty?).to be true
      end
    end
  end
end
