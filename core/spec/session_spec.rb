# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/session"

RSpec.describe RAAF::Session do
  describe "#initialize" do
    it "creates session with auto-generated ID" do
      session = described_class.new
      
      expect(session.id).to be_a(String)
      expect(session.id).not_to be_empty
      expect(session.messages).to eq([])
      expect(session.metadata).to eq({})
    end
    
    it "creates session with provided ID" do
      custom_id = "custom-session-123"
      session = described_class.new(id: custom_id)
      
      expect(session.id).to eq(custom_id)
    end
    
    it "creates session with initial messages" do
      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" }
      ]
      session = described_class.new(messages: messages)
      
      expect(session.messages.size).to eq(2)
    end
    
    it "sets timestamps" do
      session = described_class.new
      
      expect(session.created_at).to be_a(Time)
      expect(session.updated_at).to be_a(Time)
    end
  end

  describe "#add_message" do
    let(:session) { described_class.new }
    
    it "adds message to conversation" do
      session.add_message(role: "user", content: "Hello world")
      
      expect(session.messages.size).to eq(1)
      added_message = session.messages.first
      expect(added_message[:role]).to eq("user")
      expect(added_message[:content]).to eq("Hello world")
    end
  end

  describe "basic functionality" do
    it "manages session state" do
      session = described_class.new
      
      expect(session.message_count).to eq(0)
      
      session.add_message(role: "user", content: "Hello")
      expect(session.message_count).to eq(1)
      
      session.clear_messages
      expect(session.message_count).to eq(0)
    end
  end
end