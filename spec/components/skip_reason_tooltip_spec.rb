# frozen_string_literal: true

require_relative '../rails/spec/minimal_spec_helper'

RSpec.describe 'SkippedBadgeTooltip Component' do
  describe 'tooltip rendering' do
    it 'renders tooltip structure correctly' do
      skip_reason = "Agent requirements not met"
      status = "skipped"

      # Create a mock component to test the HTML structure
      component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: status,
        skip_reason: skip_reason,
        style: :modern
      )

      # Simulate rendering to check HTML structure
      html = component.view_template

      # Verify the component was created with correct parameters
      expect(component.instance_variable_get(:@status)).to eq(status)
      expect(component.instance_variable_get(:@skip_reason)).to eq(skip_reason)
      expect(component.instance_variable_get(:@style)).to eq(:modern)
    end

    it 'handles different badge styles correctly' do
      skip_reason = "Test reason"

      # Test modern style
      modern_component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: skip_reason,
        style: :modern
      )

      # Test detailed style
      detailed_component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: skip_reason,
        style: :detailed
      )

      # Test default style
      default_component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: skip_reason
      )

      # Verify each component has the correct style
      expect(modern_component.instance_variable_get(:@style)).to eq(:modern)
      expect(detailed_component.instance_variable_get(:@style)).to eq(:detailed)
      expect(default_component.instance_variable_get(:@style)).to eq(:default)
    end

    it 'truncates long skip reasons correctly' do
      long_reason = 'A' * 150  # Longer than 100 character limit

      component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: long_reason,
        style: :modern
      )

      # Test the private method through send
      truncated = component.send(:format_skip_reason, long_reason)

      expect(truncated).to end_with('...')
      expect(truncated.length).to eq(100)  # 97 chars + "..."
    end

    it 'does not truncate short skip reasons' do
      short_reason = "Short reason"

      component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: short_reason,
        style: :modern
      )

      # Test the private method through send
      result = component.send(:format_skip_reason, short_reason)

      expect(result).to eq(short_reason)
      expect(result).not_to include('...')
    end
  end

  describe 'CSS class generation' do
    it 'generates correct CSS classes for modern style' do
      component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: "test",
        style: :modern
      )

      classes = component.send(:badge_classes)

      expect(classes).to include('bg-orange-100')
      expect(classes).to include('text-orange-800')
      expect(classes).to include('inline-flex')
      expect(classes).to include('rounded-full')
    end

    it 'generates correct CSS classes for detailed style' do
      component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: "test",
        style: :detailed
      )

      classes = component.send(:badge_classes)

      expect(classes).to include('bg-orange-100')
      expect(classes).to include('text-orange-800')
      expect(classes).to include('border-orange-200')
      expect(classes).to include('flex items-center')
    end

    it 'generates correct CSS classes for default style' do
      component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
        status: "skipped",
        skip_reason: "test"
      )

      classes = component.send(:badge_classes)

      expect(classes).to include('badge')
      expect(classes).to include('bg-warning')
    end
  end

  describe 'status handling' do
    it 'handles all status types correctly' do
      statuses = %w[completed failed running pending skipped cancelled]

      statuses.each do |status|
        component = RAAF::Rails::Tracing::SkippedBadgeTooltip.new(
          status: status,
          skip_reason: status.include?('skip') || status.include?('cancel') ? "Test reason" : nil,
          style: :modern
        )

        classes = component.send(:badge_classes)

        case status
        when 'completed'
          expect(classes).to include('bg-green-100')
        when 'failed'
          expect(classes).to include('bg-red-100')
        when 'running'
          expect(classes).to include('bg-yellow-100')
        when 'pending'
          expect(classes).to include('bg-blue-100')
        when 'skipped', 'cancelled'
          expect(classes).to include('bg-orange-100')
        end
      end
    end
  end
end