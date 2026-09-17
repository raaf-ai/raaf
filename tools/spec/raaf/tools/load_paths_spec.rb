# frozen_string_literal: true

require "spec_helper"
require "digest"
require "raaf-tools"

# Each tool used to exist twice: at lib/raaf/<name>.rb and at lib/raaf/tools/<name>.rb,
# byte for byte. The gem only ever required the second, so a fix to the first went
# nowhere (#1182).
RSpec.describe "raaf-tools load paths" do
  lib_dir = File.expand_path("../../../lib", __dir__)

  {
    "RAAF::Tools::CodeInterpreterTool" => "raaf/tools/code_interpreter_tool.rb",
    "RAAF::Tools::ComputerTool" => "raaf/tools/computer_tool.rb",
    "RAAF::Tools::DocumentTool" => "raaf/tools/document_tool.rb",
    "RAAF::Tools::FileSearchTool" => "raaf/tools/file_search_tool.rb",
    "RAAF::Tools::LocalShellTool" => "raaf/tools/local_shell_tool.rb"
  }.each do |constant, path|
    it "defines #{constant} from #{path}" do
      file, = Object.const_source_location(constant)

      expect(file).to eq(File.join(lib_dir, path))
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
