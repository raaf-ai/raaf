# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Eval::UI::Session, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:configurations).dependent(:destroy) }
    it { is_expected.to have_many(:results).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_inclusion_of(:session_type).in_array(%w[draft saved archived]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending running completed failed cancelled]) }
  end

  describe "scopes" do
    let!(:recent_session) { create(:session, updated_at: 1.hour.ago) }
    let!(:old_session) { create(:session, updated_at: 1.week.ago) }
    let!(:saved_session) { create(:session, session_type: "saved") }
    let!(:draft_session) { create(:session, session_type: "draft") }

    describe ".recent" do
      it "returns sessions ordered by updated_at desc" do
        expect(described_class.recent).to eq([recent_session, old_session])
      end

      it "limits to 10 sessions" do
        create_list(:session, 15)
        expect(described_class.recent.count).to eq(10)
      end
    end

    describe ".saved" do
      it "returns only saved sessions" do
        expect(described_class.saved).to contain_exactly(saved_session)
      end
    end

    describe ".drafts" do
      it "returns only draft sessions" do
        expect(described_class.drafts).to contain_exactly(draft_session)
      end
    end
  end

  describe "instance methods" do
    let(:session) { build(:session) }

    describe "#running?" do
      it "returns true when status is running" do
        session.status = "running"
        expect(session).to be_running
      end

      it "returns false when status is not running" do
        session.status = "completed"
        expect(session).not_to be_running
      end
    end

    describe "#completed?" do
      it "returns true when status is completed" do
        session.status = "completed"
        expect(session).to be_completed
      end
    end

    describe "#mark_running!" do
      it "updates status to running" do
        session.save!
        session.mark_running!
        expect(session.reload.status).to eq("running")
      end
    end

    describe "#mark_completed!" do
      it "updates status to completed and sets completed_at" do
        session.save!
        freeze_time do
          session.mark_completed!
          expect(session.reload.status).to eq("completed")
          expect(session.completed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "#mark_failed!" do
      it "updates status to failed with error details" do
        session.save!
        error = StandardError.new("Test error")
        error.set_backtrace(["line 1", "line 2"])

        session.mark_failed!(error)

        expect(session.reload.status).to eq("failed")
        expect(session.error_message).to eq("Test error")
        expect(session.error_backtrace).to include("line 1")
      end
    end

    describe "#progress_percentage" do
      let(:session) { create(:session) }

      context "with no results" do
        it "returns 0" do
          expect(session.progress_percentage).to eq(0)
        end
      end

      context "with completed session" do
        it "returns 100" do
          session.update!(status: "completed")
          expect(session.progress_percentage).to eq(100)
        end
      end

      context "with partial completion" do
        it "calculates percentage based on completed results" do
          config1 = create(:session_configuration, session: session)
          config2 = create(:session_configuration, session: session)

          create(:session_result, session: session, configuration: config1, status: "completed")
          create(:session_result, session: session, configuration: config2, status: "pending")

          expect(session.progress_percentage).to eq(50)
        end
      end
    end
  end
end
