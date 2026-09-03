module CircleciTools
  class ResourceUsageAggregator
    def initialize(logger: Logger.new(STDOUT))
      @logger = logger
    end

    def aggregate(usage_data)
      return nil if usage_data.empty?

      aggregated_data = {
        cpu: { min: Float::INFINITY, max: -Float::INFINITY, sum: 0, count: 0 },
        memory_bytes: { min: Float::INFINITY, max: -Float::INFINITY, sum: 0, count: 0 }
      }

      stats = {
        tasks_processed: 0,
        samples_processed: { cpu: 0, memory: 0 }
      }

      usage_data.each do |data|
        next unless data.is_a?(Array)
        data.each do |task|
          next unless task.is_a?(Hash)
          cpu_usage = task['cpu']
          memory_usage = task['memory_bytes']

          next unless cpu_usage.is_a?(Array) && memory_usage.is_a?(Array)

          @logger.debug("Processing task with #{cpu_usage.size} CPU samples and #{memory_usage.size} memory samples")

          stats[:tasks_processed] += 1
          stats[:samples_processed][:cpu] += cpu_usage.size
          stats[:samples_processed][:memory] += memory_usage.size

          aggregated_data[:cpu][:min] = [aggregated_data[:cpu][:min], cpu_usage.min].min
          aggregated_data[:cpu][:max] = [aggregated_data[:cpu][:max], cpu_usage.max].max
          aggregated_data[:cpu][:sum] += cpu_usage.sum
          aggregated_data[:cpu][:count] += cpu_usage.size

          aggregated_data[:memory_bytes][:min] = [aggregated_data[:memory_bytes][:min], memory_usage.min].min
          aggregated_data[:memory_bytes][:max] = [aggregated_data[:memory_bytes][:max], memory_usage.max].max
          aggregated_data[:memory_bytes][:sum] += memory_usage.sum
          aggregated_data[:memory_bytes][:count] += memory_usage.size
        end
      end

      if aggregated_data[:cpu][:count].positive?
        aggregated_data[:cpu][:avg] = aggregated_data[:cpu][:sum] / aggregated_data[:cpu][:count].to_f
        aggregated_data[:memory_bytes][:avg] = aggregated_data[:memory_bytes][:sum] / aggregated_data[:memory_bytes][:count].to_f

        return {
          metrics: aggregated_data,
          stats: stats
        }
      end

      nil
    end

    def format_summary(result, jobs_total:, failed_jobs: [])
      return "No valid metrics found in the usage data." unless result

      metrics = result[:metrics]
      stats = result[:stats]

      [
        "\nResource Usage Summary:",
        "----------------------",
        "Jobs processed: #{jobs_total - failed_jobs.size}/#{jobs_total}",
        "Tasks analyzed: #{stats[:tasks_processed]}",
        "Samples analyzed: #{stats[:samples_processed][:cpu]} CPU, #{stats[:samples_processed][:memory]} memory",
        "",
        "CPU Usage:",
        "  Min: #{metrics[:cpu][:min].round(2)} cores",
        "  Max: #{metrics[:cpu][:max].round(2)} cores",
        "  Avg: #{metrics[:cpu][:avg].round(2)} cores",
        "",
        "Memory Usage:",
        "  Min: #{(metrics[:memory_bytes][:min] / 1024.0 / 1024.0).round(2)} MB",
        "  Max: #{(metrics[:memory_bytes][:max] / 1024.0 / 1024.0).round(2)} MB",
        "  Avg: #{(metrics[:memory_bytes][:avg] / 1024.0 / 1024.0).round(2)} MB",
        (failed_jobs.any? ? [
          "",
          "Warning: Failed to fetch data for #{failed_jobs.size} job#{'s' if failed_jobs.size > 1}:",
          *failed_jobs.map { |job_id| "  - #{job_id}" }
        ] : [])
      ].flatten.join("\n")
    end
  end
end
