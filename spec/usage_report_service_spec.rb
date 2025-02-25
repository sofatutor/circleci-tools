require 'spec_helper'
require 'usage_report_service'

RSpec.describe CircleciTools::UsageReportService do
  let(:service) { described_class.new(double('ApiService'), 'test_org_id', [], 600) }

  describe '#call' do
    it 'executes successfully' do
      expect { service.call }.not_to raise_error
    end
  end

  # Add more tests for other methods in UsageReportService
end
