require 'time'

module CircleciTools
  class JobAnalyzer
    RESOURCE_RAM = {
      'small' => 2048,   # in MB
      'medium' => 4096,
      'medium+' => 6144,
      'large' => 8192,
      # Add other classes if necessary
    }.freeze

    def calculate_peak_ram(jobs:)
      events = []

      jobs.each do |job|
        next unless job['started_at'] && job['stopped_at']

        start = parse_time(job['started_at'])
        end_time = parse_time(job['stopped_at'])
        ram = get_ram_claim(job)

        events << { time: start, type: 'start', ram: ram }
        events << { time: end_time, type: 'end', ram: ram }
      end

      # Sort events by time; 'end' before 'start' if times are equal
      events.sort_by! { |event| [event[:time], event[:type] == 'end' ? 0 : 1] }

      current_ram = 0
      peak_ram = 0

      events.each do |event|
        if event[:type] == 'start'
          current_ram += event[:ram]
          peak_ram = [peak_ram, current_ram].max
        else
          current_ram -= event[:ram]
        end
      end

      peak_ram
    end

    private

    def get_ram_claim(job)
      resource_class = job['executor']['resource_class'] || 'medium'  # Default to 'medium' if not specified
      RESOURCE_RAM[resource_class] || 4096  # Default to 4096 MB if class not found
    end

    def parse_time(time_str)
      Time.parse(time_str)
    rescue
      nil
    end
  end
end
