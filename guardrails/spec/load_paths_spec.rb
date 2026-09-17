# frozen_string_literal: true

require "spec_helper"
require "digest"
require "raaf/guardrails/base_guardrail"

# built_in, tripwire and base_guardrail used to exist twice: at lib/raaf/<name>.rb and
# at lib/raaf/guardrails/<name>.rb, byte for byte. The flat copies could not even load
# (lib/raaf/base.rb requires a ../errors that does not exist), so a fix to them went
# nowhere (#1182). Tripwire has no load check here: it requires a ../logging this gem
# does not ship, at either path.
RSpec.describe "raaf-guardrails load paths" do
  lib_dir = File.expand_path("../lib", __dir__)

  {
    "RAAF::Guardrails::BuiltIn" => "raaf/guardrails/built_in.rb",
    "RAAF::Guardrails::BaseGuardrail" => "raaf/guardrails/base_guardrail.rb"
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
