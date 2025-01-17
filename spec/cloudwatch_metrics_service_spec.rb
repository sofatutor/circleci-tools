require 'spec_helper'
require 'cloudwatch_metrics_service'

RSpec.describe Circleci::CloudWatchMetricsService do
  let(:service) { described_class.new(namespace: 'test_namespace') }

  describe '#upload_metrics' do
    it 'uploads metrics successfully' do
      csv_file_path = 'path/to/test_file.csv' # Mock or provide a sample file path
      expect { service.upload_metrics(csv_file_path) }.not_to raise_error
    end
  end

  # Add more tests for other methods in CloudWatchMetricsService
end
