# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Types do
  describe ".define" do
    context "with semantic types" do
      it "defines email type with regex validation" do
        result = described_class.define(:email)

        expect(result[:type]).to eq(:string)
        expect(result[:format]).to eq(:email)
        expect(result[:pattern]).to be_a(Regexp)
        expect("test@example.com").to match(result[:pattern])
        expect("invalid-email").not_to match(result[:pattern])
      end

      it "defines url type with URI format" do
        result = described_class.define(:url)

        expect(result[:type]).to eq(:string)
        expect(result[:format]).to eq(:uri)
      end

      it "defines percentage type with 0-100 range" do
        result = described_class.define(:percentage)

        expect(result[:type]).to eq(:number)
        expect(result[:minimum]).to eq(0)
        expect(result[:maximum]).to eq(100)
      end

      it "defines currency type with positive constraint and 2 decimal precision" do
        result = described_class.define(:currency)

        expect(result[:type]).to eq(:number)
        expect(result[:minimum]).to eq(0)
        expect(result[:multipleOf]).to eq(0.01)
      end

      it "defines phone type with international format pattern" do
        result = described_class.define(:phone)

        expect(result[:type]).to eq(:string)
        expect(result[:pattern]).to be_a(Regexp)
        expect("+1234567890").to match(result[:pattern])
        expect("123-456-7890").not_to match(result[:pattern])
      end

      it "defines score type with 0-100 integer range" do
        result = described_class.define(:score)

        expect(result[:type]).to eq(:integer)
        expect(result[:minimum]).to eq(0)
        expect(result[:maximum]).to eq(100)
      end

      it "defines naics_code type with 2-6 digit pattern" do
        result = described_class.define(:naics_code)

        expect(result[:type]).to eq(:string)
        expect(result[:pattern]).to be_a(Regexp)
        expect("11").to match(result[:pattern])
        expect("541511").to match(result[:pattern])
        expect("1").not_to match(result[:pattern])
        expect("1234567").not_to match(result[:pattern])
      end

      it "defines positive_integer type" do
        result = described_class.define(:positive_integer)

        expect(result[:type]).to eq(:integer)
        expect(result[:minimum]).to eq(1)
      end
    end

    context "with custom options" do
      it "merges options with semantic type definition" do
        result = described_class.define(:email, required: true, maxLength: 255)

        expect(result[:type]).to eq(:string)
        expect(result[:format]).to eq(:email)
        expect(result[:required]).to eq(true)
        expect(result[:maxLength]).to eq(255)
      end

      it "allows custom options to override semantic type defaults" do
        result = described_class.define(:percentage, minimum: 50, maximum: 75)

        expect(result[:minimum]).to eq(50)
        expect(result[:maximum]).to eq(75)
      end
    end

    context "with unknown types" do
      it "returns custom options for unknown type" do
        result = described_class.define(:custom_type, type: :string, required: true)

        expect(result[:type]).to eq(:string)
        expect(result[:required]).to eq(true)
      end

      it "handles unknown type gracefully without options" do
        result = described_class.define(:unknown)

        expect(result).to eq({})
      end
    end

    context "type validation patterns" do
      describe "email pattern" do
        let(:pattern) { described_class.define(:email)[:pattern] }

        it "matches valid email formats" do
          valid_emails = [
            "test@example.com",
            "user.name@domain.co.uk",
            "user+tag@example.org",
            "user-123@test-domain.com"
          ]

          valid_emails.each do |email|
            expect(email).to match(pattern), "Expected #{email} to match email pattern"
          end
        end

        it "rejects invalid email formats" do
          invalid_emails = [
            "invalid-email",
            "@example.com",
            "test@",
            "test..test@example.com",
            "test@example",
            ""
          ]

          invalid_emails.each do |email|
            expect(email).not_to match(pattern), "Expected #{email} to not match email pattern"
          end
        end
      end

      describe "phone pattern" do
        let(:pattern) { described_class.define(:phone)[:pattern] }

        it "matches valid international phone formats" do
          valid_phones = [
            "+1234567890",
            "+123456789012345", # 15 digits max
            "+12"
          ]

          valid_phones.each do |phone|
            expect(phone).to match(pattern), "Expected #{phone} to match phone pattern"
          end
        end

        it "rejects invalid phone formats" do
          invalid_phones = [
            "1234567890", # No +
            "+0123", # Starts with 0
            "+1234567890123456", # Too long (16 digits)
            "+1", # Too short
            "123-456-7890",
            "(123) 456-7890",
            ""
          ]

          invalid_phones.each do |phone|
            expect(phone).not_to match(pattern), "Expected #{phone} to not match phone pattern"
          end
        end
      end

      describe "naics_code pattern" do
        let(:pattern) { described_class.define(:naics_code)[:pattern] }

        it "matches valid NAICS code formats" do
          valid_codes = ["11", "541", "5415", "54151", "541511"]

          valid_codes.each do |code|
            expect(code).to match(pattern), "Expected #{code} to match NAICS pattern"
          end
        end

        it "rejects invalid NAICS code formats" do
          invalid_codes = ["1", "1234567", "ABC", "54-15", ""]

          invalid_codes.each do |code|
            expect(code).not_to match(pattern), "Expected #{code} to not match NAICS pattern"
          end
        end
      end
    end
  end

  describe "performance" do
    it "resolves types quickly" do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      1000.times do
        described_class.define(:email)
        described_class.define(:percentage)
        described_class.define(:unknown_type, type: :string)
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      expect(elapsed).to be < 0.1 # Less than 100ms for 3000 operations
    end
  end
end