require 'spec_helper'
require 'job_analyzer'

RSpec.describe CircleciTools::JobAnalyzer do
  let(:analyzer) { described_class.new }

  describe '#calculate_peak_ram' do
    it 'calculates peak RAM usage correctly' do
      jobs = [] # Mock or provide sample jobs data here
      peak_ram = analyzer.calculate_peak_ram(jobs: jobs)
      expect(peak_ram).to be_a(Numeric) # Adjust based on expected result
    end
  end

  # Add more tests for other methods in JobAnalyzer
end
