# frozen_string_literal: true

require "spec_helper"
require "digest"
require "open3"

# base_store used to exist twice: at lib/raaf/base_store.rb and at
# lib/raaf/memory/base_store.rb, byte for byte. The gem only ever required the second,
# so a fix to the first went nowhere (#1182).
RSpec.describe "raaf-memory load paths" do
  lib_dir = File.expand_path("../lib", __dir__)

  it "defines RAAF::Memory::BaseStore from raaf/memory/base_store.rb" do
    file, = Object.const_source_location("RAAF::Memory::BaseStore")

    expect(file).to eq(File.join(lib_dir, "raaf/memory/base_store.rb"))
  end

  # The flat stores are older copies nothing in the gem requires, but they are still
  # reachable by path and must not raise LoadError. Loaded in a child process: they
  # reopen RAAF::Memory::FileStore and InMemoryStore with their older method bodies.
  %w[raaf/file_store raaf/in_memory_store].each do |path|
    it "still loads #{path}" do
      output, status = Open3.capture2e(RbConfig.ruby, "-I", lib_dir, "-e", "require #{path.dump}")

      expect(status).to be_success, output
    end
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
