# frozen_string_literal: true

require "rails_helper"

# The Failed card counted SolidQueue jobs and its buttons moved RAAF's ledger
# rows, so the subtitle had to explain that the count and the control were
# about different things. They are not any more, so it does not.
RSpec.describe RAAF::Rails::Continuous::QueueList, type: :component do
  let(:queue) { RAAF::Rails::Continuous::JobQueue.new(window: 24.hours) }

  before { create_failed_job(span_id: "span-failed") }

  it "offers both halves of what it promises, on the rows it lists" do
    render_inline described_class.new(queue: queue)

    expect(page).to have_content("They stay here until they are requeued or discarded")
    expect(page).to have_css("form[action='/raaf/continuous/queue/retry_failed']")
    expect(page).to have_css("form[action='/raaf/continuous/queue/discard_failed']")
  end

  it "no longer explains which of two tables each half of the card speaks for" do
    render_inline described_class.new(queue: queue)

    expect(page).to have_no_content("from SolidQueue")
    expect(page).to have_no_content("which is a different list")
  end
end
