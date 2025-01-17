require 'aws-sdk-cloudwatchlogs'
require 'time'
require 'csv'
require 'json'
require_relative 'retryable'
require 'tty-prompt'
require 'date'

module CircleciTools
  class LogUploader
    MAX_THREADS = 5

    include Retryable

    def initialize(log_group_name, dry_run: false)
      @log_group_name = log_group_name
      @dry_run = dry_run
      @client = Aws::CloudWatchLogs::Client.new

      ensure_log_group_exists
    end

    def upload_file(file_path)
      events = generate_events(file_path)
      events.sort_by! { |event| event[:timestamp] }

      grouped_events = group_events_by_date(events)

      if @dry_run
        handle_dry_run(grouped_events)
      else
        upload_grouped_events(grouped_events, file_path)
      end
    end

    private

    def generate_events(file_path)
      events = []
      interval = 10 # seconds

      CSV.foreach(file_path, headers: true) do |row|
        queued_at = Time.parse(row['queued_at'])
        started_at = Time.parse(row['started_at']) rescue nil
        stopped_at = Time.parse(row['stopped_at']) rescue nil

        next unless queued_at && started_at && stopped_at

        # Initialize current_time to the next 10-second interval after queued_at
        current_time = align_time_to_next_interval(queued_at, interval)
        end_time = stopped_at

        until current_time >= end_time
          state = determine_state(current_time, started_at, stopped_at)

          log_data = {
            job_number: row['job_number'],
            state: state,
            name: row['name'],
            total_ram: row['total_ram'],
            total_cpus: row['total_cpus'],
          }

          events << {
            timestamp: current_time.to_i * 1000,
            message: log_data.to_json
          }

          current_time += interval
        end

        completed_time = align_time_to_next_interval(stopped_at, interval)
        log_data = {
          job_number: row['job_number'],
          state: 'completed',
          name: row['name'],
          total_ram: row['total_ram'],
          total_cpus: row['total_cpus'],
        }

        events << {
          timestamp: completed_time.to_i * 1000,
          message: log_data.to_json
        }
      end

      events
    rescue => e
      puts "Error generating events: #{e.message}"
      []
    end

    # Extracted Method: Group Events by Date
    def group_events_by_date(events)
      events.group_by do |event|
        Time.at(event[:timestamp] / 1000).utc.strftime('%Y-%m-%d')
      end
    end

    # Extracted Method: Handle Dry Run for Grouped Events
    def handle_dry_run(grouped_events)
      # Determine the range of dates
      dates = grouped_events.keys.sort
      from_date = dates.first
      to_date = dates.last
      output_file = "tmp/circleci-job_events-#{from_date}_to_#{to_date}.csv"

      CSV.open(output_file, 'w') do |csv|
        # Define CSV headers based on log_data fields
        csv << ['timestamp', 'job_number', 'state', 'name', 'total_ram', 'total_cpus']

        grouped_events.each do |date, events|
          events.each do |event|
            log_data = JSON.parse(event[:message])
            timestamp = Time.at(event[:timestamp] / 1000).utc.iso8601
            csv << [
              timestamp,
              log_data['job_number'],
              log_data['state'],
              log_data['name'],
              log_data['total_ram'],
              log_data['total_cpus']
            ]
          end
        end
      end
      puts "Dry run enabled: All events stored in #{output_file}"
    rescue => e
      puts "Error during dry run: #{e.message}"
    end

    # Extracted Method: Upload Grouped Events to CloudWatch
    def upload_grouped_events(grouped_events, file_path)
      grouped_events.each do |date, events|
        log_stream_name = "jobs-#{date}"
        ensure_log_stream_exists(log_stream_name)

        upload_events_to_stream(events, log_stream_name, date)
      end
      puts "Uploaded #{file_path} to CloudWatch log streams in log group #{@log_group_name}"
    rescue => e
      puts "Error uploading events: #{e.message}"
    end

    def determine_state(current_time, started_at, stopped_at)
      if current_time < started_at
        'running'
      elsif current_time >= started_at && current_time < stopped_at
        'running'
      elsif current_time >= stopped_at
        'completed'
      else
        'unknown'
      end
    end

    # Aligns a given time to the next 10-second interval and returns a Time object
    def align_time_to_next_interval(time, interval)
      aligned_seconds = (time.to_f / interval).ceil * interval
      Time.at(aligned_seconds).utc
    end

    # Extracted Method: Ensure Log Group Exists
    def ensure_log_group_exists
      log_group = @client.describe_log_groups(log_group_name_prefix: @log_group_name).log_groups.find { |lg| lg.log_group_name == @log_group_name }

      unless log_group
        if $stdin.tty?
          prompt = TTY::Prompt.new
          create = prompt.yes?("Log group '#{@log_group_name}' does not exist. Would you like to create it?")

          if create
            @client.create_log_group(log_group_name: @log_group_name)
            puts "Created log group '#{@log_group_name}'."
          else
            abort("Log group '#{@log_group_name}' does not exist. Exiting.")
          end
        else
          abort("Log group '#{@log_group_name}' does not exist and no interactive prompt available. Exiting.")
        end
      end
    end

    # Modify ensure_log_stream_exists to handle deletion of existing log streams with prompt
    def ensure_log_stream_exists(log_stream_name)
      log_stream = @client.describe_log_streams(
        log_group_name: @log_group_name,
        log_stream_name_prefix: log_stream_name
      ).log_streams.find { |stream| stream.log_stream_name == log_stream_name }

      if log_stream
        if $stdin.tty?
          prompt = TTY::Prompt.new
          delete = prompt.yes?("Log stream '#{log_stream_name}' already exists in log group '#{@log_group_name}'. Would you like to delete it and create a new one?")

          if delete
            @client.delete_log_stream(log_group_name: @log_group_name, log_stream_name: log_stream_name)
            puts "Deleted existing log stream '#{log_stream_name}'."
            @client.create_log_stream(log_group_name: @log_group_name, log_stream_name: log_stream_name)
            puts "Created new log stream '#{log_stream_name}' in log group '#{@log_group_name}'."
          else
            abort("Log stream '#{log_stream_name}' already exists. Exiting.")
          end
        else
          abort("Log stream '#{log_stream_name}' already exists in log group '#{@log_group_name}' and no interactive prompt available. Exiting.")
        end
      else
        @client.create_log_stream(log_group_name: @log_group_name, log_stream_name: log_stream_name)
        puts "Created log stream '#{log_stream_name}' in log group '#{@log_group_name}'."
      end
    end

    # Extracted Method: Upload Events to a Specific Log Stream
    def upload_events_to_stream(events, log_stream_name, date)
      batches = events.each_slice(1_000).to_a
      threads = []

      batches.each_with_index do |events_batch, index|
        threads << Thread.new do
          with_retries do
            params = {
              log_events: events_batch,
              log_group_name: @log_group_name,
              log_stream_name: log_stream_name
            }

            # Get the sequence token for the log stream
            response = @client.describe_log_streams(
              log_group_name: @log_group_name,
              log_stream_name_prefix: log_stream_name
            )
            log_stream = response.log_streams.find { |stream| stream.log_stream_name == log_stream_name }
            if log_stream && log_stream.upload_sequence_token
              params[:sequence_token] = log_stream.upload_sequence_token
            end

            # Upload the log events
            @client.put_log_events(params)
          end
          puts "Uploaded batch #{index + 1}/#{batches.size} for date #{date} to CloudWatch."
        end

        if threads.size >= MAX_THREADS
          threads.each(&:join)
          threads.clear
        end
      end

      threads.each(&:join)
    end

    def send_log(log_group_name, log_stream_name, message)
      params = {
        log_events: [{
          timestamp: (Time.now.to_f * 1000).to_i,
          message: message
        }],
        log_group_name: log_group_name,
        log_stream_name: log_stream_name
      }

      response = @client.describe_log_streams(
        log_group_name: log_group_name,
        log_stream_name_prefix: log_stream_name
      )
      log_stream = response.log_streams.find { |stream| stream.log_stream_name == log_stream_name }
      if log_stream && log_stream.upload_sequence_token
        params[:sequence_token] = log_stream.upload_sequence_token
      end

      @client.put_log_events(params)
    end
  end
end
