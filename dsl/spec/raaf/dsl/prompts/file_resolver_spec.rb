# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe RAAF::DSL::PromptResolvers::FileResolver do
  let(:temp_dir) { Dir.mktmpdir }
  let(:resolver) { described_class.new(paths: [temp_dir]) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#can_resolve?" do
    it "returns true for .md files" do
      expect(resolver.can_resolve?("prompt.md")).to be true
    end

    it "returns true for .markdown files" do
      expect(resolver.can_resolve?("prompt.markdown")).to be true
    end

    it "returns true for existing prompt files" do
      File.write(File.join(temp_dir, "test.md"), "content")
      expect(resolver.can_resolve?("test")).to be true
    end

    it "returns true for hash with markdown type" do
      expect(resolver.can_resolve?(type: :markdown, file: "test.md")).to be true
    end

    it "returns false for non-markdown files" do
      expect(resolver.can_resolve?("prompt.txt")).to be false
    end
  end

  describe "#resolve" do
    context "with simple markdown" do
      let(:prompt_file) { File.join(temp_dir, "simple.md") }

      before do
        File.write(prompt_file, "Hello {{name}}!")
      end

      it "creates prompt with user message" do
        result = resolver.resolve("simple.md", name: "World")

        expect(result).to be_a(RAAF::DSL::Prompt)
        expect(result.id).to eq("simple")
        expect(result.messages).to eq([
                                        { role: "user", content: "Hello World!" }
                                      ])
      end
    end

    context "with sections" do
      let(:prompt_file) { File.join(temp_dir, "sections.md") }

      before do
        content = <<~MD
          # System
          You are a helpful assistant.

          # User
          Help me with {{task}}.
        MD
        File.write(prompt_file, content)
      end

      it "creates prompt with system and user messages" do
        result = resolver.resolve("sections.md", task: "coding")

        expect(result.messages).to eq([
                                        { role: "system", content: "You are a helpful assistant." },
                                        { role: "user", content: "Help me with coding." }
                                      ])
      end
    end

    context "with frontmatter" do
      let(:prompt_file) { File.join(temp_dir, "frontmatter.md") }

      before do
        content = <<~MD
          ---
          id: custom-id
          version: 2.0
          category: support
          ---
          # System
          Support agent prompt
        MD
        File.write(prompt_file, content)
      end

      it "uses metadata from frontmatter" do
        result = resolver.resolve("frontmatter.md")

        expect(result.id).to eq("custom-id")
        expect(result.version).to eq(2.0)
        expect(result.metadata["category"]).to eq("support")
      end
    end
  end
end
