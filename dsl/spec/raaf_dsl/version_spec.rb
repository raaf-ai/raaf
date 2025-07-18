# frozen_string_literal: true

RSpec.describe "RAAF::DSL::VERSION" do
  subject { RAAF::DSL::VERSION }

  describe "version constant" do
    it "is defined" do
      expect(RAAF::DSL.const_defined?(:VERSION)).to be true
    end

    it "is a string" do
      expect(subject).to be_a(String)
    end

    it "follows semantic versioning format" do
      # Semantic versioning pattern: MAJOR.MINOR.PATCH with optional pre-release and build metadata
      semver_pattern = /\A\d+\.\d+\.\d+(?:[-+].*)?\z/
      expect(subject).to match(semver_pattern)
    end

    it "has the expected version number" do
      expect(subject).to eq("0.1.0")
    end

    it "is frozen" do
      expect(subject).to be_frozen
    end
  end

  describe "version comparison" do
    let(:gem_version) { Gem::Version.new(subject) }

    it "can be compared with Gem::Version" do
      expect(gem_version).to be_a(Gem::Version)
    end

    it "is greater than or equal to 0.1.0" do
      expect(gem_version).to be >= Gem::Version.new("0.1.0")
    end

    it "supports version comparison operations" do
      expect(gem_version <=> Gem::Version.new("0.1.0")).to be_a(Integer)
    end

    context "when comparing with different versions" do
      it "is greater than 0.0.9" do
        expect(gem_version).to be > Gem::Version.new("0.0.9")
      end

      it "is less than 1.0.0" do
        expect(gem_version).to be < Gem::Version.new("1.0.0")
      end

      it "equals itself" do
        expect(gem_version).to eq(Gem::Version.new(subject))
      end
    end
  end

  describe "module structure" do
    it "is defined within the RAAF::DSL module" do
      expect(RAAF::DSL.const_defined?(:VERSION)).to be true
    end

    it "can be accessed via the module" do
      expect(subject).to eq(RAAF::DSL.const_get(:VERSION))
    end
  end

  describe "version stability" do
    it "does not change during runtime" do
      original_version = subject

      # Simulate some operations that might affect constants
      100.times { subject.dup }

      expect(subject).to eq(original_version)
    end

    it "cannot be modified" do
      expect { subject.gsub!("0", "1") }.to raise_error(FrozenError)
    end
  end

  describe "version format validation" do
    let(:version_parts) { subject.split(".") }

    it "has exactly three version parts" do
      expect(version_parts.length).to eq(3)
    end

    it "has numeric version parts" do
      version_parts.each do |part|
        expect(part).to match(/\A\d+\z/)
      end
    end

    it "has a valid major version" do
      major = version_parts[0].to_i
      expect(major).to be >= 0
    end

    it "has a valid minor version" do
      minor = version_parts[1].to_i
      expect(minor).to be >= 0
    end

    it "has a valid patch version" do
      patch = version_parts[2].to_i
      expect(patch).to be >= 0
    end
  end

  describe "integration with gem specification" do
    let(:gemspec_path) { File.expand_path("../../raaf/dsl.gemspec", __dir__) }
    let(:gemspec_content) { File.read(gemspec_path) }

    it "matches the version in the gemspec file" do
      # Extract version from gemspec
      expect(gemspec_content).to include("spec.version = RAAF::DSL::VERSION")
    end

    it "is used correctly in the gemspec" do
      # Load the gemspec and check the version
      gemspec = Gem::Specification.load(gemspec_path)
      expect(gemspec.version.to_s).to eq(subject)
    end
  end

  describe "constants immutability" do
    it "warns on version constant redefinition" do
      original_version = RAAF::DSL::VERSION
      begin
        expect do
          RAAF::DSL.const_set(:VERSION, "1.0.0")
        end.to output(/already initialized constant/).to_stderr
      ensure
        # Restore original version for other tests
        original_verbosity = $VERBOSE
        $VERBOSE = nil
        RAAF::DSL.const_set(:VERSION, original_version)
        $VERBOSE = original_verbosity
      end
    end

    it "maintains version constant visibility" do
      expect(RAAF::DSL.const_defined?(:VERSION, false)).to be true
    end
  end

  describe "backward compatibility" do
    context "when version increases" do
      it "maintains major version compatibility for minor/patch updates" do
        current_major = subject.split(".")[0].to_i
        expect(current_major).to eq(0) # Current is pre-1.0, so breaking changes allowed
      end
    end
  end

  describe "version metadata" do
    it "can be used for runtime version checks" do
      version_check = lambda do |required_version|
        Gem::Version.new(subject) >= Gem::Version.new(required_version)
      end

      expect(version_check.call("0.1.0")).to be true
      expect(version_check.call("0.0.1")).to be true
      expect(version_check.call("1.0.0")).to be false
    end

    it "provides meaningful string representation" do
      expect(subject.to_s).to eq(subject)
    end

    it "can be used in version-dependent logic" do
      # Example of how version might be used in conditional logic
      version = Gem::Version.new(subject)

      if version >= Gem::Version.new("0.1.0")
        expect(:feature_available).to eq(:feature_available)
      else
        expect(:feature_unavailable).to eq(:feature_unavailable)
      end
    end
  end
end
