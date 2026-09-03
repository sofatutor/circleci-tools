require 'spec_helper'

RSpec.describe CircleciTools::ApiService do
  let(:api_token) { 'test_token' }
  let(:org) { 'test_org' }
  let(:project) { 'test_project' }
  let(:connection) { double('Faraday::Connection') }

  subject { described_class.new(api_token: api_token, org: org, project: project) }

  before do
    allow(subject).to receive(:connection).and_return(connection)
  end

  describe '#fetch_pipelines' do
    it 'fetches pipelines successfully' do
      response_body = { 'items' => [{}] }.to_json
      allow(connection).to receive(:get).with(any_args).and_return(double(body: response_body, status: 200, headers: {}))

      result = subject.fetch_pipelines(days: 30)
      expect(result).to be_an(Array)
    end

    it 'handles API errors gracefully' do
      allow(connection).to receive(:get).and_return(double(body: { message: "Invalid token provided." }.to_json, status: 401))

      expect { subject.fetch_pipelines(days: 30) }.to raise_error(StandardError, "API Error")
    end
  end

  describe '#fetch_jobs' do
    it 'fetches jobs for a given pipeline' do
      response_body = { items: [] }.to_json
      pipeline_id = 'test_pipeline_id'
      allow(connection).to receive(:get).and_return(double(body: response_body, status: 200, headers: {}))

      result = subject.fetch_jobs(pipeline_id)
      expect(result).to be_an(Array)
    end

    it 'handles API errors gracefully' do
      pipeline_id = 'test_pipeline_id'
      allow(connection).to receive(:get).and_return(double(body: { message: "Invalid token provided." }.to_json, status: 401))

      expect { subject.fetch_jobs(pipeline_id) }.to raise_error(StandardError, "API Error")
    end
  end

  describe '#fetch_workflow_jobs' do
    it 'fetches jobs for a given workflow' do
      response_body = { items: [] }.to_json
      workflow_id = 'test_workflow_id'
      allow(connection).to receive(:get).and_return(double(body: response_body, status: 200, headers: {}))

      result = subject.fetch_workflow_jobs(workflow_id)
      expect(result).to be_an(Array)
    end

    it 'handles API errors gracefully' do
      workflow_id = 'test_workflow_id'
      allow(connection).to receive(:get).and_return(double(body: { message: "Invalid token provided." }.to_json, status: 401))

      expect { subject.fetch_workflow_jobs(workflow_id) }.to raise_error(StandardError, "API Error")
    end
  end

  describe '#fetch_job_details' do
    it 'fetches job details for a given job' do
      response_body = { 'details' => 'some details' }.to_json
      job = { 'project_slug' => 'test_project_slug', 'job_number' => 123 }
      allow(connection).to receive(:get).and_return(double(body: response_body, status: 200, headers: {}))

      result = subject.fetch_job_details(job)
      expect(result).to be_a(Hash)
    end

    it 'handles API errors gracefully' do
      job = { 'project_slug' => 'test_project_slug', 'job_number' => 123 }
      allow(connection).to receive(:get).and_return(double(body: { message: "Invalid token provided." }.to_json, status: 401))

      expect { subject.fetch_job_details(job) }.to raise_error(StandardError, "API Error")
    end
  end

  describe '#fetch_all_jobs' do
    it 'fetches all jobs for given pipelines' do
      response_body = { items: [] }.to_json
      pipelines = [{ 'id' => 'test_pipeline_id' }]
      allow(connection).to receive(:get).and_return(double(body: response_body, status: 200))

      result = subject.fetch_all_jobs(pipelines)
      expect(result).to be_an(Array)
    end

    it 'handles API errors gracefully' do
      pipelines = [{ 'id' => 'test_pipeline_id' }]
      allow(connection).to receive(:get).and_raise(StandardError.new("API Error"))
      stub_const('CircleciTools::Retryable::MAX_RETRIES', 0)
      expect(subject.fetch_all_jobs(pipelines)).to eq([])
    end
  end

  describe '#create_usage_export_job' do
    it 'creates a usage export job' do
      response_body = { 'job_id' => '12345' }.to_json
      allow(connection).to receive(:get).and_return(double(body: response_body, status: 200))
      org_id = 'test_org_id'
      start_time = '2023-01-01T00:00:00Z'
      end_time = '2023-01-31T23:59:59Z'
      allow(connection).to receive(:post).and_return(double(body: response_body, status: 201, headers: {}))

      result = subject.create_usage_export_job(org_id: org_id, start_time: start_time, end_time: end_time, shared_org_ids: [])
      expect(result).to be_a(Hash)
    end

    it 'handles API errors gracefully' do
      org_id = 'test_org_id'
      start_time = '2023-01-01T00:00:00Z'
      end_time = '2023-01-31T23:59:59Z'
      allow(connection).to receive(:post).and_return(double(body: { message: "Invalid token provided." }.to_json, status: 401))

      expect { subject.create_usage_export_job(org_id: org_id, start_time: start_time, end_time: end_time, shared_org_ids: []) }.to raise_error(StandardError, "API Error")
    end
  end

  describe '#get_usage_export_job' do
    it 'fetches a usage export job' do
      response_body = { 'job_id' => '12345' }.to_json
      org_id = 'test_org_id'
      usage_export_job_id = 'test_usage_export_job_id'
      allow(connection).to receive(:get).and_return(double(body: response_body, status: 200, headers: {}))

      result = subject.get_usage_export_job(org_id: org_id, usage_export_job_id: usage_export_job_id)
      expect(result).to be_a(Hash)
    end

    it 'handles API errors gracefully' do
      org_id = 'test_org_id'
      usage_export_job_id = 'test_usage_export_job_id'
      allow(connection).to receive(:get).and_return(double(body: { message: "Invalid token provided." }.to_json, status: 401))

      expect { subject.get_usage_export_job(org_id: org_id, usage_export_job_id: usage_export_job_id) }.to raise_error(StandardError, "API Error")
    end
  end

  describe '#fetch_resource_usage' do
    let(:job_id) { '12345' }
    let(:api_token) { 'test_token' }
    let(:org) { 'test_org' }
    let(:project) { 'test_project' }
    let(:logger) { instance_double(Logger, debug: nil, info: nil) }
    let(:service) { described_class.new(api_token: api_token, org: org, project: project, logger: logger) }
    
    context 'on successful response' do
      before do
        http_client = instance_double(Net::HTTP)
        http_response = instance_double(Net::HTTPResponse, code: '200', body: valid_resource_usage_json)
        
        allow(Net::HTTP).to receive(:start).and_yield(http_client)
        allow(http_client).to receive(:request).and_return(http_response)
      end
      
      let(:valid_resource_usage_json) {
        JSON.generate([
          {
            'cpu' => [0.1, 0.2, 0.3],
            'memory_bytes' => [100_000_000, 150_000_000, 200_000_000]
          }
        ])
      }

      it 'returns parsed resource usage data' do
        result = service.fetch_resource_usage(job_id)
        
        expect(result).to be_an(Array)
        expect(result[0]['cpu']).to eq([0.1, 0.2, 0.3])
        expect(result[0]['memory_bytes']).to eq([100_000_000, 150_000_000, 200_000_000])
      end
    end
    
    context 'on error responses' do
      [
        { code: '401', error_class: StandardError, error_message: 'Unauthorized: Please check your API token' },
        { code: '404', error_class: StandardError, error_message: 'Job not found: 12345' },
        { code: '500', error_class: StandardError, error_message: 'API Error (500): Internal Server Error' }
      ].each do |scenario|
        it "raises an error for HTTP #{scenario[:code]} response" do
          http_client = instance_double(Net::HTTP)
          http_response = instance_double(Net::HTTPResponse, code: scenario[:code], body: 'Internal Server Error')
          
          allow(Net::HTTP).to receive(:start).and_yield(http_client)
          allow(http_client).to receive(:request).and_return(http_response)
          
          expect { service.fetch_resource_usage(job_id) }.to raise_error(scenario[:error_class], scenario[:error_message])
        end
      end

      it 'raises an error when JSON parsing fails' do
        http_client = instance_double(Net::HTTP)
        http_response = instance_double(Net::HTTPResponse, code: '200', body: 'This is not valid JSON')
        
        allow(Net::HTTP).to receive(:start).and_yield(http_client)
        allow(http_client).to receive(:request).and_return(http_response)
        
        expect { service.fetch_resource_usage(job_id) }.to raise_error(StandardError, /Invalid JSON response/)
      end
      
      it 'raises an error when the HTTP request fails' do
        allow(Net::HTTP).to receive(:start).and_raise(StandardError.new('Connection timeout'))
        
        expect { service.fetch_resource_usage(job_id) }.to raise_error(StandardError, /Failed to fetch resource usage: Connection timeout/)
      end
    end
  end
end
