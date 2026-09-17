# frozen_string_literal: true

require "spec_helper"
require "digest"

# Guardrails used to exist twice: at lib/raaf/<name>.rb and at
# lib/raaf/guardrails/<name>.rb, some byte for byte, some drifted apart. The flat copies
# could not even load (lib/raaf/base.rb requires a ../errors that does not exist), so a
# fix to them went nowhere (#1182).
RSpec.describe "raaf-guardrails load paths" do
  lib_dir = File.expand_path("../lib", __dir__)

  {
    "RAAF::Guardrails::Base" => "raaf/guardrails/base.rb",
    "RAAF::Guardrails::BaseGuardrail" => "raaf/guardrails/base_guardrail.rb",
    "RAAF::Guardrails::BuiltIn" => "raaf/guardrails/built_in.rb",
    "RAAF::Guardrails::ParallelGuardrails" => "raaf/guardrails/parallel_guardrails.rb",
    "RAAF::Guardrails::PIIDetector" => "raaf/guardrails/pii_detector.rb",
    "RAAF::Guardrails::SecurityGuardrail" => "raaf/guardrails/security_guardrail.rb",
    "RAAF::Guardrails::TripwireGuardrail" => "raaf/guardrails/tripwire.rb"
  }.each do |constant, path|
    it "defines #{constant} from #{path}" do
      file, = Object.const_source_location(constant)

      expect(file).to eq(File.join(lib_dir, path))
    end
  end

  it "has no file in lib/raaf/ named like one in lib/raaf/guardrails/" do
    flat = Dir.children(File.join(lib_dir, "raaf")).grep(/\.rb\z/)
    namespaced = Dir.children(File.join(lib_dir, "raaf/guardrails"))

    expect(flat & namespaced).to be_empty
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
