module CircleciTools
  class RunnerCalculator
    attr_reader :runner_ram_gb

    def initialize(runner_ram_gb = 8)
      @runner_ram_gb = runner_ram_gb
      @runner_ram_mb = @runner_ram_gb * 1024  # Convert GB to MB
    end

    def calculate_runners(peak_ram_mb)
      (peak_ram_mb.to_f / @runner_ram_mb).ceil
    end
  end
end
