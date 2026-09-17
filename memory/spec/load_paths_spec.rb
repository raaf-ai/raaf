# frozen_string_literal: true

require "spec_helper"
require "digest"

# Stores used to exist twice: at lib/raaf/<name>.rb and at lib/raaf/memory/<name>.rb,
# some byte for byte, some drifted apart. The gem only ever required the second, so a
# fix to the first went nowhere (#1182).
RSpec.describe "raaf-memory load paths" do
  lib_dir = File.expand_path("../lib", __dir__)

  {
    "RAAF::Memory::BaseStore" => "raaf/memory/base_store.rb",
    "RAAF::Memory::FileStore" => "raaf/memory/file_store.rb",
    "RAAF::Memory::InMemoryStore" => "raaf/memory/in_memory_store.rb",
    "RAAF::Memory::MemoryManager" => "raaf/memory/memory_manager.rb"
  }.each do |constant, path|
    it "defines #{constant} from #{path}" do
      file, = Object.const_source_location(constant)

      expect(file).to eq(File.join(lib_dir, path))
    end
  end

  # Two names are shared on purpose: raaf/memory.rb is the namespace's entry file, and
  # raaf/vector_store.rb defines RAAF::VectorStore, a different class from
  # RAAF::Memory::VectorStore.
  it "has no file in lib/raaf/ named like one in lib/raaf/memory/, apart from the two that differ" do
    flat = Dir.children(File.join(lib_dir, "raaf")).grep(/\.rb\z/)
    namespaced = Dir.children(File.join(lib_dir, "raaf/memory"))

    expect(flat & namespaced).to contain_exactly("memory.rb", "vector_store.rb")
  end

  it "has no Ruby file under lib/ that is a byte-for-byte copy of another" do
    copies = Dir.glob(File.join(lib_dir, "**/*.rb"))
                .group_by { |file| Digest::SHA256.file(file).hexdigest }
                .values
                .select { |files| files.size > 1 }
                .map { |files| files.map { |file| file.delete_prefix("#{lib_dir}/") } }

    expect(copies).to be_empty
  end
end
