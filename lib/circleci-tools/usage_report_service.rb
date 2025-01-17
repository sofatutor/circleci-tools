require 'time'
require 'net/http'
require 'logger'
require 'fileutils'
require 'zlib'
require 'csv'
require_relative 'api_service'
require_relative 'retryable'

module CircleciTools
  class UsageReportService
    include Retryable

    def initialize(api_service, org_id, shared_org_ids = [], interval_seconds = 600, logger: Logger.new(STDOUT), log_level: Logger::INFO)
      @api_service = api_service
      @org_id = org_id
      @shared_org_ids = shared_org_ids
      @interval_seconds = interval_seconds
      @running = false
      @logger = logger
      @logger.level = log_level
    end

    def call(start_time: Time.now.utc - 3600, end_time: Time.now.utc, usage_export_job_id: nil)
      @logger.info("Starting usage report for org #{@org_id}...")
      @running = true

      end_time = Time.now.utc if end_time > Time.now.utc

      if usage_export_job_id
        @logger.info("Using existing usage export job ID: #{usage_export_job_id}")
        usage_data = poll_usage_export_job(usage_export_job_id)
        success = usage_data && usage_data['download_urls']
        @logger.debug("Usage data: #{usage_data}")
        files = success ? download_and_save_files(usage_data['download_urls'], start_time, end_time) : []
      else
        success, files = fetch_and_store_usage_report(start_time:, end_time:)
      end

      stop if success
      files
    end

    def stop
      @running = false
    end

    private

    def fetch_and_store_usage_report(start_time:, end_time:)
      @logger.debug("Creating usage export job for CircleCI usage from #{start_time.iso8601} to #{end_time.iso8601}...")
      export_job = @api_service.create_usage_export_job(
        org_id: @org_id,
        start_time: start_time.iso8601,
        end_time: end_time.iso8601,
        shared_org_ids: @shared_org_ids
      )
      return [false, []] unless export_job
      @logger.debug("Export job created with ID: #{export_job['usage_export_job_id']}")

      usage_export_job_id = export_job['usage_export_job_id']
      usage_data = poll_usage_export_job(usage_export_job_id)
      @logger.debug("Usage data: #{usage_data}")
      return [false, []] unless usage_data

      @logger.debug("Usage export job completed, downloading files...")
      return [false, []] unless usage_data['download_urls']

      downloaded_files = download_and_save_files(usage_data['download_urls'], start_time, end_time)
      @logger.info("Downloaded #{downloaded_files.size} file(s).")
      return [true, downloaded_files]
    end

    def poll_usage_export_job(usage_export_job_id)
      timeout = Time.now + 4 * 3600
      loop do
        break if Time.now > timeout

        job_status = @api_service.get_usage_export_job(
          org_id: @org_id,
          usage_export_job_id: usage_export_job_id
        )
        return job_status if job_status && job_status['state'] == 'completed'

        sleep 30
      end
      nil
    end

    def download_and_save_files(download_urls, start_time, end_time)
      paths = []
      start_time_str = start_time.utc.strftime('%Y%m%d%H%M')
      end_time_str = end_time.utc.strftime('%Y%m%d%H%M')
      FileUtils.mkdir_p('tmp')
      combined_csv_path = "tmp/usage_report_#{start_time_str}_to_#{end_time_str}.csv"
      CSV.open(combined_csv_path, 'w') do |csv|
        download_urls.each_with_index do |url, index|
          uri = URI(url)
          response = with_retries { Net::HTTP.get(uri) }
          gz_path = "tmp/usage_report_#{start_time_str}_to_#{end_time_str}_part_#{index + 1}.gz"
          File.open(gz_path, 'wb') { |file| file.write(response) }
          unzip_and_combine_csv(gz_path, csv)
          File.delete(gz_path) # Delete the .gz file after extraction
        end
      end
      paths << combined_csv_path
      paths
    end

    def unzip_and_combine_csv(gz_path, combined_csv)
      Zlib::GzipReader.open(gz_path) do |gz|
        CSV.new(gz).each do |row|
          combined_csv << row
        end
      end
    end
  end
end
