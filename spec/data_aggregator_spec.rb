require 'spec_helper'
require 'data_aggregator'

RSpec.describe CircleciTools::DataAggregator do
  let(:aggregator) { described_class.new([]) } # Initialize with an empty array or mock data

  describe '#generate_csv' do
    it 'generates a CSV file successfully' do
      # Mock or provide sample jobs data here
      # Example: allow(aggregator).to receive(:generate_csv).and_return(mocked_response)

      expect { aggregator.generate_csv }.not_to raise_error
    end
  end

  # Add more tests for other methods in DataAggregator
end
