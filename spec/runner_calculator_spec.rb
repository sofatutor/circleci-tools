require 'spec_helper'
require 'runner_calculator'

RSpec.describe CircleciTools::RunnerCalculator do
  let(:calculator) { described_class.new }

  describe '#calculate_runners' do
    it 'calculates the number of runners needed based on RAM' do
      peak_ram = 2048 # Example peak RAM in MB
      runners = calculator.calculate_runners(peak_ram)
      expect(runners).to be_a(Numeric) # Adjust based on expected result
    end
  end

  # Add more tests for other methods in RunnerCalculator
end
