require 'aws-sdk-cloudwatch'
require 'json'
require 'time'
require 'tty-progressbar'

module CircleciTools
  class CloudWatchMetricsService
    def initialize(namespace: 'CircleCI', dry_run: false, logger: Logger.new(STDOUT))
      @namespace = namespace
      @dry_run = dry_run
      @logger = logger
      @cloudwatch = Aws::CloudWatch::Client.new
    end

    def upload_metrics(file_path)
      events = parse_csv(file_path)
      metrics = generate_metrics(events)

      if @dry_run
        puts JSON.pretty_generate(metrics)
      else
        upload_to_cloudwatch(metrics)
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
          job_name: row['JOB_NAME'],
          started_at: started_at,
          stopped_at: stopped_at,
          run_time: (stopped_at - started_at).to_i,
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
        dimensions = [
          { name: 'Project', value: event[:project_name] },
          { name: 'WorkflowName', value: event[:workflow_name] },
          { name: 'JobName', value: event[:job_name] }
        ]

        truncated_timestamp = truncate_to_minute(event[:stopped_at])

        metrics << {
          metric_name: 'JobRunTime',
          dimensions: dimensions,
          timestamp: truncated_timestamp,
          value: event[:run_time],
          unit: 'Seconds'
        } if event[:run_time] > 0
        metrics << {
          metric_name: 'AverageRAMUtilization',
          dimensions: dimensions,
          timestamp: truncated_timestamp,
          value: event[:avg_ram],
          unit: 'Percent'
        } if event[:avg_ram] > 0
        metrics << {
          metric_name: 'MaxRAMUtilization',
          dimensions: dimensions,
          timestamp: truncated_timestamp,
          value: event[:max_ram],
          unit: 'Percent'
        } if event[:max_ram] > 0
        metrics << {
          metric_name: 'AverageCPUUtilization',
          dimensions: dimensions,
          timestamp: truncated_timestamp,
          value: event[:avg_cpu],
          unit: 'Percent'
        } if event[:avg_cpu] > 0
        metrics << {
          metric_name: 'MaxCPUUtilization',
          dimensions: dimensions,
          timestamp: truncated_timestamp,
          value: event[:max_cpu],
          unit: 'Percent'
        } if event[:max_cpu] > 0
      end
      metrics
    end

    def truncate_to_minute(time)
      Time.at(time.to_i - time.sec)
    end

    def upload_to_cloudwatch(metrics)
      bar = TTY::ProgressBar.new("Uploading [:bar] :percent :elapsed", total: metrics.size)
      metrics.each_slice(10) do |metric_batch|
        begin
          @cloudwatch.put_metric_data(
            namespace: @namespace,
            metric_data: metric_batch
          )
          bar.advance(10)
        rescue Aws::CloudWatch::Errors::ServiceError => e
          @logger.error("Failed to upload metrics: #{e.message}")
        end
      end
      @logger.info("Uploaded #{metrics.size} metrics to CloudWatch.")
    end
  end
end
