# frozen_string_literal: true

module CircleciTools
  module Kpi
    DAYS_FETCH_BATCH_SIZE = 20

    class Loader
      def initialize(client:)
        @client = client
      end

      def workflows(org:, project:, workflow_name:, branch:, limit:)
        @client.workflow_items(org:, project:, workflow_name:, branch:, limit:).map do |workflow|
          Run.new(workflow.merge('name' => workflow_name))
        end
      end

      def displayed_workflows(org:, project:, workflow_name:, branch:, range:)
        fetch_limit = DAYS_FETCH_BATCH_SIZE
        start_time, end_time = TimeWindow.for(days: range.fetch(:days), week: range[:week])
        enriched_workflows_by_id = {}
        scope = { org:, project:, workflow_name:, branch: }

        loop do
          workflows, marked_workflows = marked_workflows_for_fetch(
            fetch_limit:,
            enriched_workflows_by_id:,
            scope:
          )
          displayed = displayed_workflows_with_days_context(marked_workflows, start_time, end_time)

          return displayed if days_fetch_complete?(workflows, fetch_limit, marked_workflows, start_time, end_time)

          fetch_limit += DAYS_FETCH_BATCH_SIZE
        end
      end

      def enrich_jobs_with_parallelism(workflow, org:, project:)
        workflow.merge(
          'jobs' => parallel_map(workflow.jobs) do |job|
            job_number = job['job_number']
            next job unless job_number

            detail = @client.job_detail(org:, project:, job_number:)
            job.merge(
              'executor' => detail['executor'],
              'parallelism' => detail['parallelism'],
              'resource_class' => detail.dig('executor', 'resource_class')
            )
          end
        )
      end

      private

      def workflows_with_jobs(workflows)
        parallel_map(workflows) do |workflow|
          detail = @client.workflow_detail(workflow.id)

          workflow.merge(
            'jobs' => @client.workflow_jobs(workflow.id),
            'pipeline_id' => detail['pipeline_id'],
            'pipeline_number' => detail['pipeline_number'],
            'tag' => detail['tag'],
            'auto_rerun_number' => detail['auto_rerun_number']
          )
        end
      end

      def parallel_map(items)
        results = Array.new(items.size)

        threads = items.each_with_index.map do |item, index|
          Thread.new do
            results[index] = yield item
          end
        end

        threads.each(&:join)
        results
      end

      def sorted_workflows(workflows)
        workflows.sort_by { |workflow| workflow.created_at || Time.at(0).utc }
      end

      def connect_reruns(workflows)
        workflows.each(&:clear_rerun_metadata)

        workflows.group_by(&:pipeline_id).each do |pipeline_id, pipeline_workflows|
          next if pipeline_id.to_s.empty?

          sorted_pipeline_workflows = sorted_workflows(pipeline_workflows)

          sorted_pipeline_workflows.each_with_index do |workflow, index|
            next unless workflow.rerun?

            parent_workflow = sorted_pipeline_workflows[0...index].reverse.find(&:rerun_parent_candidate?)
            next unless parent_workflow

            workflow.rerun = true
            workflow.rerun_parent_workflow = parent_workflow
            parent_workflow.add_rerun_child(workflow)
          end
        end

        sorted_workflows(workflows)
      end

      def first_in_window_workflow(workflows, start_time, end_time)
        workflows.find { |workflow| within_time_window?(workflow, start_time, end_time) }
      end

      def context_workflow_ids_for(first_workflow)
        workflow_ids = []
        current_workflow = first_workflow

        while current_workflow&.rerun?
          workflow_ids.unshift(current_workflow.id)
          current_workflow = current_workflow.rerun_parent_workflow
        end

        workflow_ids.unshift(current_workflow.id) if current_workflow
        workflow_ids
      end

      def displayed_workflows_with_days_context(workflows, start_time, end_time)
        first_workflow = first_in_window_workflow(workflows, start_time, end_time)
        return [] unless first_workflow

        context_ids = context_workflow_ids_for(first_workflow)

        workflows.select do |workflow|
          context_ids.include?(workflow.id) || within_time_window?(workflow, start_time, end_time)
        end
      end

      def marked_workflows_for_fetch(fetch_limit:, enriched_workflows_by_id:, scope:)
        fetched = workflows(**scope, limit: fetch_limit)
        missing_workflows = fetched.reject { |workflow| enriched_workflows_by_id.key?(workflow.id) }

        workflows_with_jobs(missing_workflows).each do |workflow|
          enriched_workflows_by_id[workflow.id] = workflow
        end

        marked = connect_reruns(fetched.map { |workflow| enriched_workflows_by_id.fetch(workflow.id) })
        [fetched, marked]
      end

      def days_fetch_complete?(workflows, fetch_limit, marked_workflows, start_time, end_time)
        return true if workflows.empty?
        return true if workflows.size < fetch_limit

        first_workflow = first_in_window_workflow(marked_workflows, start_time, end_time)
        oldest_fetched_time = marked_workflows.first&.created_at
        fetched_past_start = oldest_fetched_time && oldest_fetched_time <= start_time
        has_context = !first_workflow || !first_workflow.rerun? || first_workflow.rerun_parent_workflow

        fetched_past_start && has_context
      end

      def within_time_window?(workflow, start_time, end_time)
        created_at = workflow.created_at
        created_at && created_at >= start_time && created_at < end_time
      end
    end
  end
end
