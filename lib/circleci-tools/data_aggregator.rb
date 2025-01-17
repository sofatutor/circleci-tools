module CircleciTools
  class DataAggregator
    CREDIT_COST = 0.0006

    RESOURCE_CLASS_MAP = {
      "small" => { cpus: 1, ram: 2 },
      "medium" => { cpus: 2, ram: 4 },
      "medium+" => { cpus: 3, ram: 6 },
      "large" => { cpus: 4, ram: 8 }
    }

    def initialize(jobs)
      @jobs = jobs
    end

    def generate_csv
      csv_file_path = 'tmp/jobs_aggregated.csv'

      CSV.open(csv_file_path, 'w') do |csv|
        csv << [
          'job_number', 'duration (ms)', 'duration_minutes', 'total_duration_minutes', 'queued_at',
          'started_at', 'stopped_at', 'status', 'parallelism', 'resource_class', 'name',
          'CPUs', 'RAM', 'total_ram', 'total_cpus', 'total_credits', 'total_costs'
        ]

        @jobs.each do |job|
          duration = job['duration'] || 0
          duration_minutes = duration / 1000.0 / 60.0
          parallelism = job['parallelism'] || 1
          total_duration_minutes = duration_minutes * parallelism

          resource_class = job['executor']['resource_class']
          next unless resource_class

          mapped_class = RESOURCE_CLASS_MAP[resource_class]
          next unless mapped_class

          cpus = mapped_class[:cpus] || 1
          ram = mapped_class[:ram] || 1

          total_ram = parallelism * ram
          total_cpus = parallelism * cpus
          total_credits = total_cpus * duration_minutes * 5
          total_costs = (total_credits * CREDIT_COST * parallelism).round(2)

          csv << [
            job['number'], duration, duration_minutes, total_duration_minutes, job['queued_at'],
            job['started_at'], job['stopped_at'], job['status'], parallelism, resource_class,
            job['name'], cpus, ram, total_ram, total_cpus, total_credits, total_costs
          ]
        end
      end

      puts "CSV file created at #{csv_file_path}"
    end
  end
end
