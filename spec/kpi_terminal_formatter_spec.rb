# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CircleciTools::Kpi::TerminalFormatter do
  describe '#summary_messages' do
    it 'shows the probably flaky rate from eventual successes after failed first attempts' do
      successful_workflow = workflow('successful-workflow', 'success')
      flaky_workflow = workflow('flaky-workflow', 'failed')
      rerun_workflow = workflow('rerun-workflow', 'success', rerun: true)
      failed_workflow = workflow('failed-workflow', 'failed')

      flaky_workflow.add_rerun_child(rerun_workflow)

      messages = formatter.summary_messages([successful_workflow, flaky_workflow, rerun_workflow, failed_workflow])

      expect(messages.join("\n")).to include('Probably Flaky Rate (test range)')
      expect(messages.join("\n")).to include('33%')
    end
  end

  def formatter
    described_class.new(org: 'test-org', project: 'test-project', range_label: 'test range')
  end

  def workflow(id, status, rerun: false)
    CircleciTools::Kpi::Run.new(
      'id' => id,
      'status' => status,
      'rerun' => rerun,
      'jobs' => [
        {
          'id' => "#{id}-job",
          'name' => 'test',
          'status' => status,
          'started_at' => '2026-06-03T10:00:00Z',
          'stopped_at' => '2026-06-03T10:01:00Z'
        }
      ]
    )
  end
end
