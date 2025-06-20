# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "json"

RSpec.describe OpenAIAgents::Tracer do
  let(:tracer) { described_class.new }

  describe "#initialize" do
    it "initializes with empty traces and processors" do
      expect(tracer.traces).to be_empty
      expect(tracer.instance_variable_get(:@processors)).to be_empty
    end
  end

  describe "#add_processor" do
    let(:processor) { double("processor") }

    it "adds processor to processors list" do
      tracer.add_processor(processor)

      expect(tracer.instance_variable_get(:@processors)).to include(processor)
    end

    it "accumulates multiple processors" do
      processor1 = double("processor1")
      processor2 = double("processor2")

      tracer.add_processor(processor1)
      tracer.add_processor(processor2)

      processors = tracer.instance_variable_get(:@processors)
      expect(processors).to include(processor1, processor2)
    end
  end

  describe "#trace" do
    it "creates trace entry with timestamp and event data" do
      freeze_time = Time.now.utc
      allow(Time).to receive(:now).and_return(freeze_time)

      tracer.trace("test_event", { key: "value" })

      expect(tracer.traces).to have(1).item
      trace = tracer.traces.first
      expect(trace[:timestamp]).to eq(freeze_time.iso8601)
      expect(trace[:event_type]).to eq("test_event")
      expect(trace[:data]).to eq({ key: "value" })
    end

    it "stores traces in order" do
      tracer.trace("first_event")
      tracer.trace("second_event")
      tracer.trace("third_event")

      expect(tracer.traces.map { |t| t[:event_type] }).to eq(%w[first_event second_event third_event])
    end

    it "handles empty data" do
      tracer.trace("empty_event")

      trace = tracer.traces.first
      expect(trace[:data]).to eq({})
    end

    it "calls all registered processors" do
      processor1 = double("processor1")
      processor2 = double("processor2")

      expect(processor1).to receive(:call) do |trace_entry|
        expect(trace_entry[:event_type]).to eq("test_event")
        expect(trace_entry[:data]).to eq({ test: "data" })
      end

      expect(processor2).to receive(:call) do |trace_entry|
        expect(trace_entry[:event_type]).to eq("test_event")
        expect(trace_entry[:data]).to eq({ test: "data" })
      end

      tracer.add_processor(processor1)
      tracer.add_processor(processor2)

      tracer.trace("test_event", { test: "data" })
    end

    it "returns the trace entry" do
      result = tracer.trace("test_event", { key: "value" })

      expect(result).to be_a(Hash)
      expect(result[:event_type]).to eq("test_event")
      expect(result[:data]).to eq({ key: "value" })
    end

    it "continues even if processor raises error" do
      failing_processor = double("failing_processor")
      working_processor = double("working_processor")

      allow(failing_processor).to receive(:call).and_raise(StandardError, "Processor failed")
      expect(working_processor).to receive(:call)

      tracer.add_processor(failing_processor)
      tracer.add_processor(working_processor)

      expect { tracer.trace("test_event") }.not_to raise_error
      expect(tracer.traces).to have(1).item
    end
  end

  describe "#clear" do
    it "removes all traces" do
      tracer.trace("event1")
      tracer.trace("event2")
      tracer.trace("event3")

      expect(tracer.traces).to have(3).items

      tracer.clear

      expect(tracer.traces).to be_empty
    end
  end

  describe "#to_json" do
    it "returns traces as pretty JSON" do
      tracer.trace("test_event", { key: "value" })

      json_string = tracer.to_json
      parsed = JSON.parse(json_string)

      expect(parsed).to be_an(Array)
      expect(parsed.first["event_type"]).to eq("test_event")
      expect(parsed.first["data"]["key"]).to eq("value")
    end

    it "returns empty array JSON for no traces" do
      json_string = tracer.to_json
      parsed = JSON.parse(json_string)

      expect(parsed).to eq([])
    end
  end

  describe "#save_to_file" do
    let(:temp_file) { Tempfile.new("tracer_test") }

    after do
      temp_file.unlink
    end

    it "saves traces to file as JSON" do
      tracer.trace("test_event", { key: "value" })

      tracer.save_to_file(temp_file.path)

      content = File.read(temp_file.path)
      parsed = JSON.parse(content)

      expect(parsed).to be_an(Array)
      expect(parsed.first["event_type"]).to eq("test_event")
    end

    it "overwrites existing file content" do
      File.write(temp_file.path, "old content")

      tracer.trace("new_event")
      tracer.save_to_file(temp_file.path)

      content = File.read(temp_file.path)
      expect(content).not_to include("old content")

      parsed = JSON.parse(content)
      expect(parsed.first["event_type"]).to eq("new_event")
    end
  end
end

RSpec.describe OpenAIAgents::ConsoleProcessor do
  let(:processor) { described_class.new }

  describe "#call" do
    it "prints trace entry to stdout" do
      trace_entry = {
        timestamp: "2023-01-01T00:00:00Z",
        event_type: "test_event",
        data: { key: "value" }
      }

      expected_output = "[2023-01-01T00:00:00Z] test_event: {:key=>\"value\"}\n"

      expect { processor.call(trace_entry) }.to output(expected_output).to_stdout
    end

    it "handles empty data" do
      trace_entry = {
        timestamp: "2023-01-01T00:00:00Z",
        event_type: "empty_event",
        data: {}
      }

      expected_output = "[2023-01-01T00:00:00Z] empty_event: {}\n"

      expect { processor.call(trace_entry) }.to output(expected_output).to_stdout
    end

    it "handles complex data structures" do
      trace_entry = {
        timestamp: "2023-01-01T00:00:00Z",
        event_type: "complex_event",
        data: { nested: { array: [1, 2, 3], hash: { deep: "value" } } }
      }

      expect { processor.call(trace_entry) }.to output(/complex_event/).to_stdout
    end
  end
end

RSpec.describe OpenAIAgents::FileProcessor do
  let(:temp_file) { Tempfile.new("file_processor_test") }
  let(:processor) { described_class.new(temp_file.path) }

  after do
    temp_file.unlink
  end

  describe "#initialize" do
    it "stores filename" do
      expect(processor.instance_variable_get(:@filename)).to eq(temp_file.path)
    end
  end

  describe "#call" do
    it "appends trace entry as JSON to file" do
      trace_entry = {
        timestamp: "2023-01-01T00:00:00Z",
        event_type: "test_event",
        data: { key: "value" }
      }

      processor.call(trace_entry)

      content = File.read(temp_file.path)
      parsed = JSON.parse(content)

      expect(parsed["event_type"]).to eq("test_event")
      expect(parsed["data"]["key"]).to eq("value")
    end

    it "appends multiple entries on separate lines" do
      trace_entry1 = {
        timestamp: "2023-01-01T00:00:00Z",
        event_type: "event1",
        data: { num: 1 }
      }

      trace_entry2 = {
        timestamp: "2023-01-01T00:00:01Z",
        event_type: "event2",
        data: { num: 2 }
      }

      processor.call(trace_entry1)
      processor.call(trace_entry2)

      lines = File.readlines(temp_file.path)
      expect(lines).to have(2).items

      parsed1 = JSON.parse(lines[0])
      parsed2 = JSON.parse(lines[1])

      expect(parsed1["event_type"]).to eq("event1")
      expect(parsed2["event_type"]).to eq("event2")
    end

    it "preserves existing file content" do
      File.write(temp_file.path, "{\"existing\": \"content\"}\n")

      trace_entry = {
        timestamp: "2023-01-01T00:00:00Z",
        event_type: "new_event",
        data: {}
      }

      processor.call(trace_entry)

      content = File.read(temp_file.path)
      lines = content.split("\n")

      expect(lines[0]).to include("existing")
      expect(lines[1]).to include("new_event")
    end

    it "creates file if it doesn't exist" do
      new_file_path = File.join(Dir.tmpdir, "new_trace_file.json")

      begin
        processor = described_class.new(new_file_path)

        trace_entry = {
          timestamp: "2023-01-01T00:00:00Z",
          event_type: "test_event",
          data: {}
        }

        processor.call(trace_entry)

        expect(File.exist?(new_file_path)).to be true
        content = File.read(new_file_path)
        parsed = JSON.parse(content)
        expect(parsed["event_type"]).to eq("test_event")
      ensure
        FileUtils.rm_f(new_file_path)
      end
    end
  end
end

RSpec.describe "Tracer integration" do
  let(:tracer) { OpenAIAgents::Tracer.new }
  let(:temp_file) { Tempfile.new("integration_test") }

  after do
    temp_file.unlink
  end

  it "works with both console and file processors" do
    console_processor = OpenAIAgents::ConsoleProcessor.new
    file_processor = OpenAIAgents::FileProcessor.new(temp_file.path)

    tracer.add_processor(console_processor)
    tracer.add_processor(file_processor)

    expect do
      tracer.trace("integration_event", { test: "data", number: 42 })
    end.to output(/integration_event/).to_stdout

    # Check file content
    content = File.read(temp_file.path)
    parsed = JSON.parse(content)

    expect(parsed["event_type"]).to eq("integration_event")
    expect(parsed["data"]["test"]).to eq("data")
    expect(parsed["data"]["number"]).to eq(42)

    # Check tracer internal storage
    expect(tracer.traces).to have(1).item
    expect(tracer.traces.first[:event_type]).to eq("integration_event")
  end

  it "handles multiple events with different processors" do
    file_processor = OpenAIAgents::FileProcessor.new(temp_file.path)
    tracer.add_processor(file_processor)

    tracer.trace("event1", { sequence: 1 })
    tracer.trace("event2", { sequence: 2 })
    tracer.trace("event3", { sequence: 3 })

    lines = File.readlines(temp_file.path)
    expect(lines).to have(3).items

    lines.each_with_index do |line, index|
      parsed = JSON.parse(line)
      expect(parsed["event_type"]).to eq("event#{index + 1}")
      expect(parsed["data"]["sequence"]).to eq(index + 1)
    end

    expect(tracer.traces).to have(3).items
  end

  it "maintains chronological order" do
    tracer.trace("first")
    sleep(0.001) # Ensure different timestamps
    tracer.trace("second")
    sleep(0.001)
    tracer.trace("third")

    timestamps = tracer.traces.map { |t| Time.parse(t[:timestamp]) }
    expect(timestamps).to eq(timestamps.sort)

    event_types = tracer.traces.map { |t| t[:event_type] }
    expect(event_types).to eq(%w[first second third])
  end
end
