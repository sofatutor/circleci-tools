# lib/circleci_concurrency_evaluator/circleci_service.rb

require 'faraday'
require 'json'
require 'base64'
require 'logger'
require_relative 'retryable'

module CircleciTools
  class ApiService
    include Retryable
    BASE_URL = 'https://circleci.com'
    MAX_THREADS = 10

    def initialize(api_token:, org:, project:, vcs_type: 'gh', logger: Logger.new(STDOUT))
      @api_token = api_token
      @vcs_type = vcs_type
      @org = org
      @project = project
      @logger = logger
    end

    def fetch_pipelines(days: nil)
      pipelines = []
      page_token = nil
      cutoff_time = days ? Time.now - (days * 24 * 60 * 60) : nil

      loop do
        url = '/api/v2/pipeline'
        params = {
          'org-slug' => "#{@vcs_type}/#{@org}",
          'page-token' => page_token,
          'mine' => false
        }

        response = with_retries { connection.get(url, params.compact, headers) }
        break unless response
        raise 'API Error' unless response.status == 200

        data = JSON.parse(response.body)

        pipelines.concat(data['items'])

        page_token = data['next_page_token']
        break unless page_token

        break if cutoff_time && data['items'].any? { |pipeline| Time.parse(pipeline['created_at']) < cutoff_time }
      end

      pipelines
    end

    def fetch_jobs(pipeline_id)
      jobs = []
      page_token = nil

      loop do
        url = "/api/v2/pipeline/#{pipeline_id}/workflow"
        params = {}
        params['page-token'] = page_token if page_token

        response = with_retries { connection.get(url, params, headers) }
        break unless response
        raise 'API Error' unless response.status == 200

        data = JSON.parse(response.body)
        workflows = data['items']

        threads = workflows.map do |workflow|
          Thread.new do
            workflow_jobs = fetch_workflow_jobs(workflow['id'])
            jobs.concat(workflow_jobs)
          end
        end

        threads.each(&:join)

        page_token = data['next_page_token']
        break unless page_token
      end

      jobs
    end

    def fetch_workflow_jobs(workflow_id)
      url = "/api/v2/workflow/#{workflow_id}/job"

      response = with_retries { connection.get(url, nil, headers) }
      return [] unless response
      raise 'API Error' unless response.status == 200

      data = JSON.parse(response.body)
      data['items']
    end

    def fetch_job_details(job)
      url = "/api/v2/project/#{job['project_slug']}/job/#{job['job_number']}"

      response = with_retries { connection.get(url, nil, headers) }
      return nil unless response
      raise 'API Error' unless response.status == 200

      JSON.parse(response.body)
    end

    def fetch_all_jobs(pipelines)
      all_jobs = []
      semaphore = Mutex.new
      threads = []

      pipelines.each_with_index do |pipeline, index|
        threads << Thread.new do
          jobs = fetch_jobs(pipeline['id'])
          jobs.each do |job|
            next unless job['job_number']
            next if job['status'] == 'not_run'

            job_details = fetch_job_details(job)
            next unless job_details
            next unless job_details['duration']

            semaphore.synchronize { all_jobs << job_details }
          end
          @logger.info("Fetched jobs for pipeline #{index + 1}/#{pipelines.size} (ID: #{pipeline['id']})")
        end

        if threads.size >= MAX_THREADS
          threads.each(&:join)
          threads.clear
        end
      end

      threads.each(&:join)
      all_jobs
    end

    def create_usage_export_job(org_id:, start_time:, end_time:, shared_org_ids: [])
      url = "/api/v2/organizations/#{org_id}/usage_export_job"
      body = { start: start_time, end: end_time, shared_org_ids: shared_org_ids }
      response = with_retries { connection.post(url, body.to_json, headers.merge('Content-Type' => 'application/json')) }
      return nil unless response
      raise 'API Error' unless response.status == 201

      JSON.parse(response.body)
    end

    def get_usage_export_job(org_id:, usage_export_job_id:)
      url = "/api/v2/organizations/#{org_id}/usage_export_job/#{usage_export_job_id}"
      response = with_retries { connection.get(url, nil, headers) }
      return nil unless response
      raise 'API Error' unless response.status == 200

      JSON.parse(response.body)
    end

    private

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
      end
    end

    def headers
      {
        'Circle-Token' => @api_token,
        'Accept' => 'application/json'
      }
    end
  end
end
