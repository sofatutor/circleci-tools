require 'spec_helper'
require 'resource_usage_aggregator'

RSpec.describe CircleciTools::ResourceUsageAggregator do
  let(:logger) { instance_double(Logger, debug: nil, info: nil) }
  let(:aggregator) { described_class.new(logger: logger) }

  describe '#aggregate' do
    context 'with empty data' do
      it 'returns nil when input data is empty' do
        expect(aggregator.aggregate([])).to be_nil
      end
    end

    context 'with valid data' do
      let(:usage_data) {
        [
          [
            {
              'cpu' => [0.1, 0.2, 0.3, 0.4, 0.5],
              'memory_bytes' => [100_000_000, 150_000_000, 200_000_000]
            },
            {
              'cpu' => [0.3, 0.4, 0.5, 0.6],
              'memory_bytes' => [250_000_000, 300_000_000]
            }
          ],
          [
            {
              'cpu' => [0.2, 0.3, 0.4],
              'memory_bytes' => [120_000_000, 180_000_000]
            }
          ]
        ]
      }

      it 'aggregates resource usage data correctly' do
        result = aggregator.aggregate(usage_data)
        
        expect(result).not_to be_nil
        expect(result[:metrics][:cpu][:min]).to eq(0.1)
        expect(result[:metrics][:cpu][:max]).to eq(0.6)
        # Fix the expected average value to match the actual calculation:
        # Sum of CPU values: 0.1+0.2+0.3+0.4+0.5+0.3+0.4+0.5+0.6+0.2+0.3+0.4 = 4.2
        # Count: 12
        # Average: 4.2/12 = 0.35
        expect(result[:metrics][:cpu][:avg]).to be_within(0.001).of(0.35)
        
        expect(result[:metrics][:memory_bytes][:min]).to eq(100_000_000)
        expect(result[:metrics][:memory_bytes][:max]).to eq(300_000_000)
        expect(result[:metrics][:memory_bytes][:avg]).to be_within(1).of(185_714_285.71)
        
        expect(result[:stats][:tasks_processed]).to eq(3)
        expect(result[:stats][:samples_processed][:cpu]).to eq(12)
        expect(result[:stats][:samples_processed][:memory]).to eq(7)
      end
    end

    context 'with invalid data' do
      it 'handles non-array data gracefully' do
        result = aggregator.aggregate([{ 'invalid' => 'data' }])
        expect(result).to be_nil
      end

      it 'skips non-hash tasks' do
        result = aggregator.aggregate([['not a hash']])
        expect(result).to be_nil
      end

      it 'skips tasks with missing data' do
        result = aggregator.aggregate([[{ 'missing_data' => true }]])
        expect(result).to be_nil
      end

      it 'skips tasks with non-array metrics' do
        result = aggregator.aggregate([[{ 'cpu' => 'not an array', 'memory_bytes' => 'not an array' }]])
        expect(result).to be_nil
      end
    end
  end

  describe '#format_summary' do
    let(:aggregated_result) {
      {
        metrics: {
          cpu: {
            min: 0.1,
            max: 0.6,
            avg: 0.36666
          },
          memory_bytes: {
            min: 100_000_000,
            max: 300_000_000,
            avg: 185_714_285.71
          }
        },
        stats: {
          tasks_processed: 3,
          samples_processed: {
            cpu: 12,
            memory: 7
          }
        }
      }
    }

    it 'formats summary correctly' do
      summary = aggregator.format_summary(aggregated_result, jobs_total: 5, failed_jobs: ['job1', 'job2'])
      
      expect(summary).to include('Resource Usage Summary:')
      expect(summary).to include('Jobs processed: 3/5')
      expect(summary).to include('Tasks analyzed: 3')
      expect(summary).to include('Samples analyzed: 12 CPU, 7 memory')
      
      expect(summary).to include('CPU Usage:')
      expect(summary).to include('Min: 0.1 cores')
      expect(summary).to include('Max: 0.6 cores')
      expect(summary).to include('Avg: 0.37 cores')
      
      expect(summary).to include('Memory Usage:')
      expect(summary).to include('Min: 95.37 MB')
      expect(summary).to include('Max: 286.1 MB')
      expect(summary).to include('Avg: 177.11 MB')
      
      expect(summary).to include('Warning: Failed to fetch data for 2 jobs:')
      expect(summary).to include('  - job1')
      expect(summary).to include('  - job2')
    end

    it 'formats summary without failures' do
      summary = aggregator.format_summary(aggregated_result, jobs_total: 3, failed_jobs: [])
      
      expect(summary).to include('Jobs processed: 3/3')
      expect(summary).not_to include('Warning: Failed to fetch data')
    end

    it 'handles nil result' do
      summary = aggregator.format_summary(nil, jobs_total: 5, failed_jobs: [])
      expect(summary).to eq('No valid metrics found in the usage data.')
    end
  end
end
