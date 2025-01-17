module CircleciTools
  module Retryable
    MAX_RETRIES = 5
    BACKOFF_FACTOR = 0.5

    def with_retries
      retries = 0
      begin
        yield
      rescue => e
        if retries < MAX_RETRIES
          retries += 1
          backoff_time = BACKOFF_FACTOR * (2 ** retries)
          puts "Thread #{Thread.current.object_id}: Retry ##{retries} after #{backoff_time} seconds due to: #{e.message}"
          sleep backoff_time
          retry
        else
          puts "Thread #{Thread.current.object_id}: Error: #{e.message}"
        end
      end
    end
  end
end
