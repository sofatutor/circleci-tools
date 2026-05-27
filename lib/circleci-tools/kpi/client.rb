# frozen_string_literal: true

require 'cgi'
require 'connection_pool'
require 'faraday'
require 'faraday/net_http_persistent'
require 'json'

module CircleciTools
  module Kpi
    DEFAULT_HOST = 'https://circleci.com'
    POOL_SIZE = 10
    POOL_TIMEOUT = 5

    class Client
      def initialize(token:, host: DEFAULT_HOST)
        @api_base_url = "#{host.sub(%r{/*$}, '')}/api/v2/"
        @token = token
        @connection_pool = ConnectionPool.new(size: POOL_SIZE, timeout: POOL_TIMEOUT) do
          Faraday.new(url: @api_base_url) do |connection|
            connection.headers['Accept'] = 'application/json'
            connection.headers['Circle-Token'] = @token
            connection.adapter :net_http_persistent
          end
        end
      end

      def workflow_items(org:, project:, workflow_name:, branch:, limit:)
        workflows = []
        page_token = nil
        escaped_workflow_name = CGI.escape(workflow_name)

        loop do
          query = {}
          query['page-token'] = page_token if page_token

          if branch
            query['branch'] = branch
          else
            query['all-branches'] = true
          end

          response = request_json(
            :get,
            "insights/#{escaped_project_slug(org, project)}/workflows/#{escaped_workflow_name}",
            query:
          )
          items = response.fetch('items', [])
          break if items.empty?

          batch_size = limit - workflows.size
          workflows.concat(items.first(batch_size))

          break if workflows.size >= limit

          page_token = response['next_page_token']
          break if page_token.to_s.empty?
        end

        workflows
          .sort_by { |workflow| parse_time(workflow['created_at']) || Time.at(0).utc }
          .first(limit)
      end

      def workflow_jobs(workflow_id)
        jobs = []
        page_token = nil

        loop do
          query = {}
          query['page-token'] = page_token if page_token

          response = request_json(:get, "workflow/#{workflow_id}/job", query:)
          jobs.concat(response.fetch('items', []))

          page_token = response['next_page_token']
          break if page_token.to_s.empty?
        end

        jobs
      end

      def workflow_detail(workflow_id)
        request_json(:get, "workflow/#{workflow_id}")
      end

      def job_detail(org:, project:, job_number:)
        request_json(:get, "project/#{escaped_project_slug(org, project)}/job/#{job_number}")
      end

      private

      def escaped_project_slug(org, project)
        ['gh', org, project].map { |segment| CGI.escape(segment) }.join('/')
      end

      def request_json(method, path, query: nil)
        response = @connection_pool.with do |connection|
          case method
          when :get
            connection.get(path, query)
          else
            raise ArgumentError, "Unsupported method: #{method}"
          end
        end

        return {} if response.body.to_s.empty? && response.success?
        return JSON.parse(response.body) if response.success?

        abort "CircleCI API request failed (#{response.status}): #{error_message_for(response)}"
      end

      def error_message_for(response)
        parsed = JSON.parse(response.body)
        (parsed['message'] || parsed['error'] || response.body).to_s.strip
      rescue JSON::ParserError
        response.body.to_s.strip
      end

      def parse_time(value)
        Time.iso8601(value).utc if value
      rescue ArgumentError
        nil
      end
    end
  end
end
