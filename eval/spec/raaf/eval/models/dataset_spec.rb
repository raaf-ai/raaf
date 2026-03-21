# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::Dataset, type: :model do
  describe "validations" do
    it "requires name" do
      dataset = build(:dataset, name: nil)
      expect(dataset).not_to be_valid
      expect(dataset.errors[:name]).to include("can't be blank")
    end

    it "requires valid status" do
      dataset = build(:dataset, status: "invalid")
      expect(dataset).not_to be_valid
    end

    it "accepts valid status values" do
      %w[active archived].each do |status|
        dataset = build(:dataset, status: status)
        expect(dataset).to be_valid
      end
    end

    it "enforces unique name + version combination" do
      create(:dataset, name: "my_dataset", version: 1)
      duplicate = build(:dataset, name: "my_dataset", version: 1)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#add_item" do
    let(:dataset) { create(:dataset) }

    it "creates a dataset item and increments count" do
      item = dataset.add_item(
        input: { messages: [{ role: "user", content: "Hello" }] },
        expected_output: { messages: [{ role: "assistant", content: "Hi!" }] }
      )

      expect(item).to be_persisted
      expect(dataset.reload.items_count).to eq(1)
    end
  end

  describe "#add_item_from_span" do
    let(:dataset) { create(:dataset) }

    it "creates item from span data" do
      span_data = {
        span_id: "span_123",
        trace_id: "trace_456",
        input_messages: [{ role: "user", content: "Test" }],
        output_messages: [{ role: "assistant", content: "Response" }]
      }

      item = dataset.add_item_from_span(span_data)
      expect(item).to be_persisted
      expect(item.input["messages"]).to eq(span_data[:input_messages])
    end
  end

  describe "#create_new_version!" do
    let(:dataset) { create(:dataset, name: "versioned_dataset", version: 1) }

    before do
      dataset.add_item(input: { query: "Q1" }, expected_output: { answer: "A1" })
      dataset.add_item(input: { query: "Q2" }, expected_output: { answer: "A2" })
    end

    it "creates a new version with duplicated items" do
      new_version = dataset.create_new_version!(created_by: "tester")

      expect(new_version.version).to eq(2)
      expect(new_version.name).to eq("versioned_dataset")
      expect(new_version.items_count).to eq(2)
      expect(new_version.dataset_items.count).to eq(2)
    end
  end

  describe "#archive!" do
    it "archives the dataset" do
      dataset = create(:dataset, status: "active")
      dataset.archive!
      expect(dataset.status).to eq("archived")
    end
  end

  describe "#latest_version?" do
    it "returns true for the latest version" do
      create(:dataset, name: "test_ds", version: 1)
      v2 = create(:dataset, name: "test_ds", version: 2)

      expect(v2.latest_version?).to be true
    end
  end

  describe "scopes" do
    it "filters active datasets" do
      active = create(:dataset, status: "active")
      create(:dataset, status: "archived")

      expect(described_class.active).to include(active)
      expect(described_class.active.count).to eq(1)
    end
  end
end
