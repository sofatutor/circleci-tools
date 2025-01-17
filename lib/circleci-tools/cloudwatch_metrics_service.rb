require 'aws-sdk-cloudwatch'
require 'digest'
require 'json'
require 'set'
require 'time'
require 'tty-progressbar'

module CircleciTools
  class CloudWatchMetricsService
    UPLOAD_BATCH_SIZE = 20
    METRICS_DIGEST_FILENAME = 'cloud-watch-metrics-digests.txt'

    def initialize(namespace: 'CircleCI', dry_run: false, logger: Logger.new(STDOUT), s3_bucket: nil)
      @namespace = namespace
      @dry_run = dry_run
      @logger = logger
      @cloudwatch = Aws::CloudWatch::Client.new
      @s3_bucket = s3_bucket
      @s3_client = Aws::S3::Client.new if @s3_bucket
    end

    def upload_metrics(file_path)
      events = parse_csv(file_path)

      if @dry_run
        metrics = generate_metrics(events)
        puts JSON.pretty_generate(metrics)
      else
        events.group_by { |event| event[:project_name] }.each do |project_name, project_events|
          metrics = generate_metrics(project_events)
          upload_to_cloudwatch(project_name, metrics)
        end
      end
    end

    private

    def parse_csv(file_path)
      events = []
      two_weeks_ago = Time.now - (14 * 24 * 60 * 60)
      CSV.foreach(file_path, headers: true) do |row|
        next unless row['JOB_RUN_STARTED_AT'].to_i > 0 && row['JOB_RUN_STOPPED_AT'].to_i > 0

        started_at = Time.parse(row['JOB_RUN_STARTED_AT'])
        stopped_at = Time.parse(row['JOB_RUN_STOPPED_AT'])
        next if stopped_at < two_weeks_ago

        events << {
          project_name: row['PROJECT_NAME'],
          workflow_name: row['WORKFLOW_NAME'],
          branch: row['VCS_BRANCH'],
          job_name: row['JOB_NAME'],
          job_status: row['JOB_BUILD_STATUS'],
          started_at: started_at,
          stopped_at: stopped_at,
          run_time: (stopped_at - started_at).to_i,
          compute_credits_used: row['COMPUTE_CREDITS'].to_i,
          avg_ram: row['MEDIAN_RAM_UTILIZATION_PCT'].to_i,
          max_ram: row['MAX_RAM_UTILIZATION_PCT'].to_i,
          avg_cpu: row['MEDIAN_CPU_UTILIZATION_PCT'].to_i,
          max_cpu: row['MAX_CPU_UTILIZATION_PCT'].to_i
        }
      end
      events
    end

    def generate_metrics(events)
      metrics = []
      events.each do |event|
        workflow_dimensions = [
          { name: 'WorkflowName', value: event[:workflow_name] }
        ]

        branch_dimensions = [
          { name: 'Branch', value: event[:branch] },
          { name: 'JobName', value: event[:job_name] }
        ]

        truncated_timestamp = truncate_to_minute(event[:stopped_at])

        metrics << {
          metric_name: 'JobRunTime',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: event[:run_time],
          unit: 'Seconds'
        } if event[:run_time] > 0
        metrics << {
          metric_name: 'AverageRAMUtilization',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: event[:avg_ram],
          unit: 'Percent'
        } if event[:avg_ram] > 0
        metrics << {
          metric_name: 'MaxRAMUtilization',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: event[:max_ram],
          unit: 'Percent'
        } if event[:max_ram] > 0
        metrics << {
          metric_name: 'AverageCPUUtilization',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: event[:avg_cpu],
          unit: 'Percent'
        } if event[:avg_cpu] > 0
        metrics << {
          metric_name: 'MaxCPUUtilization',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: event[:max_cpu],
          unit: 'Percent'
        } if event[:max_cpu] > 0
        metrics << {
          metric_name: 'JobSucceeded',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: 1,
          unit: 'Count'
        } if event[:job_status] == 'success'
        metrics << {
          metric_name: 'JobFailed',
          dimensions: branch_dimensions,
          timestamp: truncated_timestamp,
          value: 1,
          unit: 'Count'
        } if event[:job_status] == 'failed'
        metrics << {
          metric_name: 'ComputeCreditsUsed',
          dimensions: workflow_dimensions,
          timestamp: truncated_timestamp,
          value: event[:compute_credits_used],
          unit: 'Count'
        } if event[:compute_credits_used] > 0
      end
      metrics
    end

    def truncate_to_minute(time)
      Time.at(time.to_i - time.sec)
    end

    def upload_to_cloudwatch(project_name, metrics)
      bar = TTY::ProgressBar.new("Uploading [:bar] :percent :elapsed", total: metrics.size)

      existing_digests = load_existing_digests
      new_metrics = []
      new_digests = []

      metrics.each do |metric|
        digest = Digest::MD5.hexdigest(metric.to_s)
        next if existing_digests.include?(digest)

        new_metrics << metric
        new_digests << digest
      end

      new_metrics.each_slice(UPLOAD_BATCH_SIZE) do |metric_batch|
        begin
          @cloudwatch.put_metric_data(
            namespace: "#{@namespace}/#{project_name}",
            metric_data: metric_batch
          )
          bar.advance(metric_batch.size)
        rescue Aws::CloudWatch::Errors::ServiceError => e
          @logger.error("Failed to upload metrics: #{e.message}")
        end
      end

      store_new_digests(new_digests)

      @logger.info("Uploaded #{new_metrics.size} metrics to CloudWatch for project #{project_name}.")
    end

    private

    def load_existing_digests
      if @s3_bucket
        begin
          resp = @s3_client.get_object(bucket: @s3_bucket, key: "#{@namespace.downcase}/#{METRICS_DIGEST_FILENAME}")
          Set.new(resp.body.read.split("\n"))
        rescue Aws::S3::Errors::NoSuchKey
          Set.new
        end
      else
        digest_file = File.join('tmp', METRICS_DIGEST_FILENAME)
        if File.exist?(digest_file)
          Set.new(digest_file).map(&:chomp)
        else
          Set.new
        end
      end
    end

    def store_new_digests(new_digests)
      return if new_digests.empty?

      if @s3_bucket
        old_digests = load_existing_digests
        merged_digests = (old_digests + new_digests).to_a.uniq.join("\n")
        @s3_client.put_object(bucket: @s3_bucket, key: "#{@namespace.downcase}/#{METRICS_DIGEST_FILENAME}", body: merged_digests)
      else
        File.open(File.join('tmp', METRICS_DIGEST_FILENAME), 'a') do |file|
          new_digests.each { |digest| file.puts digest }
        end
      end
    end
  end
end
