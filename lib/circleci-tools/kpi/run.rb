# frozen_string_literal: true

module CircleciTools
  module Kpi
    MANUAL_RERUN_GAP_THRESHOLD = 10 * 60
    CREDITS_PER_MINUTE_BY_RESOURCE_CLASS = {
      'small' => 5,
      'medium' => 10,
      'medium+' => 15,
      'large' => 20
    }.freeze

    class Run
      attr_writer :rerun_parent_workflow
      attr_reader :rerun_parent_workflow

      def initialize(attributes)
        @attributes = attributes.dup
      end

      def merge(attributes)
        self.class.new(@attributes.merge(attributes))
      end

      def id
        @attributes.fetch('id')
      end

      def status
        @attributes.fetch('status', 'unknown')
      end

      def pipeline_id
        @attributes['pipeline_id']
      end

      def pipeline_number
        @attributes['pipeline_number']
      end

      def branch
        @attributes['branch']
      end

      def jobs
        Array(@attributes['jobs'])
      end

      def created_at
        parse_time(@attributes['created_at'])
      end

      def stopped_at
        parse_time(@attributes['stopped_at'])
      end

      def display_time
        stopped_at || created_at
      end

      def rerun?
        @attributes['rerun'] || @attributes['auto_rerun_number'].to_i.positive? || @attributes['tag'].to_s.include?('rerun')
      end

      def rerun=(value)
        @attributes['rerun'] = value
      end

      def rerun_children
        Array(@attributes['rerun_children'])
      end

      def add_rerun_child(workflow)
        @attributes['rerun_children'] ||= []
        @attributes['rerun_children'] << workflow
      end

      def rerun_parent_candidate?
        %w[failed error canceled unauthorized].include?(status)
      end

      def clear_rerun_metadata
        @attributes.delete('rerun')
        @attributes.delete('rerun_parent_workflow')
        @attributes.delete('rerun_children')
      end

      def duration
        return unless created_at

        (workflow_stopped_at - created_at).to_i
      end

      def displayed_total_duration
        return duration unless rerun?
        return if manual_rerun?

        started_at = root_rerun_parent_workflow.created_at
        return unless started_at

        (workflow_stopped_at - started_at).to_i
      end

      def formatted_job_duration_for(job)
        return '^' if reused_rerun_job?(job)
        return if job['status'] == 'not_run'
        return 'n/a' if job_has_missing_stop_time?(job)

        duration = job_duration_for(job)
        return unless duration

        format_duration(duration)
      end

      def numeric_job_duration_for(job)
        aggregate_duration = job['aggregate_duration']
        return aggregate_duration if aggregate_duration

        return if reused_rerun_job?(job)
        return if job['status'] == 'not_run'
        return if job_has_missing_stop_time?(job)

        job_duration_for(job)
      end

      def numeric_job_cost_credits_for(job)
        duration = numeric_job_duration_for(job)
        return unless duration

        credits_per_minute = CREDITS_PER_MINUTE_BY_RESOURCE_CLASS[job_resource_class_for(job)]
        return unless credits_per_minute

        (duration.to_f / 60) * job_parallelism_for(job) * credits_per_minute
      end

      def counted_job_count
        jobs.count { |job| job['status'] != 'not_run' }
      end

      def job_dependencies_for(job)
        dependencies = Array(job['dependencies'])
        return dependencies unless dependencies.empty?

        job['requires'].is_a?(Hash) ? job['requires'].keys : []
      end

      def manual_rerun?
        rerun_parent_workflow && (inferred_manual_rerun? || rerun_parent_workflow.manual_rerun?)
      end

      private

      def workflow_stopped_at
        stopped_at || Time.now.utc
      end

      def inferred_manual_rerun?
        return false unless created_at

        parent_stopped_at = rerun_parent_workflow&.stopped_at
        parent_stopped_at && (created_at - parent_stopped_at) > MANUAL_RERUN_GAP_THRESHOLD
      end

      def root_rerun_parent_workflow
        current_workflow = self
        current_workflow = current_workflow.rerun_parent_workflow while current_workflow.rerun_parent_workflow
        current_workflow
      end

      def job_duration_for(job)
        started_at = parse_time(job['started_at'])
        return unless started_at

        stopped_at = parse_time(job['stopped_at'])
        return (Time.now.utc - started_at).to_i if %w[running failing].include?(job['status'])
        return unless stopped_at

        (stopped_at - started_at).to_i
      end

      def job_has_missing_stop_time?(job)
        parse_time(job['started_at']) && parse_time(job['stopped_at']).nil? &&
          !%w[running failing].include?(job['status'])
      end

      def parent_job_for(job)
        return unless rerun_parent_workflow

        rerun_parent_workflow.jobs.find { |parent_job| parent_job['name'] == job['name'] }
      end

      def reused_rerun_job?(job)
        parent_job = parent_job_for(job)
        return false unless parent_job
        return false unless job['status'] == 'success' && parent_job['status'] == 'success'

        parent_job['id'] == job['id'] || parent_job['job_number'] == job['job_number']
      end

      def job_parallelism_for(job)
        parallelism = job['parallelism'].to_i
        parallelism.positive? ? parallelism : 1
      end

      def job_resource_class_for(job)
        job['resource_class'] || job.dig('executor', 'resource_class')
      end

      def parse_time(value)
        Time.iso8601(value).utc if value
      rescue ArgumentError
        nil
      end

      def format_duration(seconds)
        total_seconds = seconds.to_i
        '%d:%02d' % [total_seconds / 60, total_seconds % 60]
      end
    end
  end
end
