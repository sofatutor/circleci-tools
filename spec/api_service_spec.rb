require 'spec_helper'
require 'api_service'

RSpec.describe Circleci::ApiService do
  let(:api_token) { 'test_token' }
  let(:org) { 'test_org' }
  let(:project) { 'test_project' }
  let(:service) { described_class.new(api_token: api_token, org: org, project: project) }

  describe '#fetch_pipelines' do
    it 'fetches pipelines successfully' do
      # Mock the API call and response here
      # Example: allow(service).to receive(:fetch_pipelines).and_return(mocked_response)

      result = service.fetch_pipelines(days: 30)
      expect(result).to be_an(Array) # Adjust based on expected response
    end
  end

  # Add more tests for other methods in ApiService
end
