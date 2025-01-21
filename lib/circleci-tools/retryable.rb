module CircleciTools
  module Retryable
    MAX_RETRIES = 5
    BACKOFF_FACTOR = 0.5
    MAX_BACKOFF_TIME = 60

    def with_retries(max_retries: MAX_RETRIES)
      retries = 0
      begin
        yield
      rescue => e
        if retries < max_retries
          retries += 1
          backoff_time = [BACKOFF_FACTOR * (2 ** retries), MAX_BACKOFF_TIME].min.floor
          retry_logger.info "Retry ##{retries} after #{backoff_time} seconds"
          retry_logger.debug "Thread #{Thread.current.object_id}: Error: #{e.message}"
          sleep backoff_time
          retry
        else
          retry_logger.warn "Thread #{Thread.current.object_id}: Error: #{e.message}"
        end
      end
    end

    def retry_logger
      @logger ||= Logger.new(STDOUT)
    end
  end
end
