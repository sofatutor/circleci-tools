# frozen_string_literal: true

require 'term/ansicolor'

module CircleciTools
  module Kpi
    CIRCLECI_APP_URL = 'https://app.circleci.com'
    TIMESTAMP_FORMAT = '%Y-%m-%d %H:%M'
    TIMESTAMP_WIDTH = '0000-00-00 00:00'.size
    STATUS_WIDTH = 10
    IN_PREFIX_WIDTH = ' in '.size
    SUMMARY_VALUE_START = STATUS_WIDTH + 1 + TIMESTAMP_WIDTH + IN_PREFIX_WIDTH
    BASE_TREE_PREFIX = ' ' * 4
    TOTAL_DURATION_WIDTH = '00:00'.size

    class TerminalFormatter
      def initialize(org:, project:, range_label:, links: false, show_branch: false)
        @org = org
        @project = project
        @range_label = range_label
        @links = links
        @show_branch = show_branch
      end

      def render_workflow(workflow)
        status_text = format("%-#{STATUS_WIDTH}s", workflow.status.upcase)
        message = "#{tree_prefix_for(workflow)}#{colorize(status_text, color_for(workflow.status))}"

        message << " #{format_time(workflow.display_time)}" if workflow.display_time

        if workflow.manual_rerun?
          message << "   #{colorize('manual', :blue)}"
        else
          total_duration = formatted_total_duration_for(workflow)
          message << " in #{total_duration}" if total_duration
        end

        duration_summary = duration_summary_for(workflow)
        message << " #{duration_summary}" unless duration_summary.empty?
        message << " #{colorize(workflow.branch, :yellow)}" if @show_branch && workflow.branch
        message << " #{workflow_url_for(workflow)}" if @links

        message
      end

      def summary_messages(workflows)
        blueprint_workflows = workflows
        successful_workflows = workflows.select { |w| w.status == 'success' }
        failed_workflows = workflows.select { |w| w.status == 'failed' }
        first_attempt_workflows = workflows.reject { |w| w.status == 'canceled' || w.rerun? }

        messages = []
        messages.concat(duration_summary_messages_for(successful_workflows, workflows, blueprint_workflows))
        messages.concat(average_summary_messages_for(successful_workflows, failed_workflows, blueprint_workflows))
        messages.concat(p95_summary_messages_for(successful_workflows, failed_workflows, blueprint_workflows))
        cost_message = cost_summary_message_for(workflows, successful_workflows, blueprint_workflows)
        messages << cost_message if cost_message
        messages.concat(
          success_rate_summary_messages_for(
            first_attempt_workflows, blueprint_workflows,
            prepend_spacing: messages.any?
          )
        )
        messages.concat(
          chain_duration_summary_messages_for(
            first_attempt_workflows, blueprint_workflows,
            prepend_spacing: messages.any?
          )
        )

        messages
      end

      private

      def tree_prefix_for(workflow)
        return orphan_rerun_prefix_for(workflow) if workflow.rerun? && !workflow.rerun_parent_workflow
        return root_prefix_for(workflow) unless workflow.rerun_parent_workflow

        ancestors = ancestor_chain_for(workflow)
        depth = ancestors.size
        prefix = +''

        ancestors[0...-1].each_with_index do |ancestor, position|
          prefix << tree_prefix_segment(ancestor, ancestors[position + 1])
        end

        connector = tree_connector_for(workflow)
        prefix << tree_connector_prefix(workflow, connector, depth)
        prefix
      end

      def root_prefix_for(workflow)
        workflow.rerun_children.any? ? '█   ' : BASE_TREE_PREFIX
      end

      def orphan_rerun_prefix_for(workflow)
        workflow.rerun_children.any? ? '└█  ' : '└─  '
      end

      def ancestor_chain_for(workflow)
        ancestors = []
        current = workflow.rerun_parent_workflow
        while current
          ancestors.unshift(current)
          current = current.rerun_parent_workflow
        end
        ancestors
      end

      def tree_prefix_segment(ancestor, descendant)
        ancestor.rerun_children.last == descendant ? ' ' : '│'
      end

      def tree_connector_for(workflow)
        workflow.rerun_parent_workflow.rerun_children.last == workflow ? '└' : '├'
      end

      def tree_connector_prefix(workflow, connector, depth)
        has_children = workflow.rerun_children.any?
        if depth == 1
          has_children ? "#{connector}█  " : "#{connector}─  "
        else
          has_children ? "#{connector}█ " : "#{connector}─ "
        end
      end

      def color_for(status)
        case status
        when 'success' then :green
        when 'failed', 'error', 'unauthorized' then :red
        when 'running' then :blue
        else :yellow
        end
      end

      def colorize(text, color)
        Term::ANSIColor.public_send(color, text)
      end

      def format_time(time)
        time.getlocal.strftime(TIMESTAMP_FORMAT)
      end

      def formatted_total_duration_for(workflow)
        total_duration = workflow.displayed_total_duration
        return unless total_duration

        formatted = format_duration(total_duration).rjust(TOTAL_DURATION_WIDTH)
        return colorize(formatted, :yellow) if workflow.rerun?

        formatted
      end

      def stage_entries_for(workflow)
        jobs_by_id = workflow.jobs.to_h { |job| [job['id'], job] }
        stage_indexes = {}

        workflow.jobs.filter_map do |job|
          formatted_duration = workflow.formatted_job_duration_for(job)
          next unless formatted_duration

          {
            formatted_duration: formatted_duration,
            name: job['name'],
            numeric_duration: workflow.numeric_job_duration_for(job),
            stage_index: job_stage_index_for(job['id'], workflow, jobs_by_id, stage_indexes),
            started_at: parse_time(job['started_at']),
            status: job['status']
          }
        end
      end

      def raw_stage_entries_for(workflow)
        jobs_by_id = workflow.jobs.to_h { |job| [job['id'], job] }
        stage_indexes = {}

        workflow.jobs.map do |job|
          {
            name: job['name'],
            stage_index: job_stage_index_for(job['id'], workflow, jobs_by_id, stage_indexes)
          }
        end
      end

      def job_stage_index_for(job_id, workflow, jobs_by_id, stage_indexes)
        return stage_indexes[job_id] if stage_indexes.key?(job_id)

        job = jobs_by_id[job_id]
        return 0 unless job

        dependencies = workflow.job_dependencies_for(job).select { |dep_id| jobs_by_id.key?(dep_id) }
        stage_indexes[job_id] = if dependencies.empty?
                                  0
                                else
                                  dependencies.map do |dep_id|
                                    job_stage_index_for(dep_id, workflow, jobs_by_id, stage_indexes)
                                  end.max + 1
                                end
      end

      def duration_summary_for(workflow)
        stage_entries_for(workflow)
          .group_by { |entry| entry[:stage_index] }
          .sort_by { |stage_index, _| stage_index }
          .map do |_, entries|
            sorted = entries.sort_by { |entry| entry[:name] }
            longest = longest_stage_duration_for(sorted)
            formatted = sorted.map { |entry| formatted_stage_entry(entry, longest, highlight_longest: true) }
            "[#{formatted.join('; ')}]"
          end.join(' -> ')
      end

      def summary_stage_blueprint_for(workflows)
        workflows
          .flat_map { |workflow| raw_stage_entries_for(workflow) }
          .group_by { |entry| entry[:name] }
          .map { |name, entries| [entries.map { |e| e[:stage_index] }.min, name] }
          .group_by(&:first)
          .sort_by { |stage_index, _| stage_index }
          .map { |_, entries| entries.map(&:last).sort }
      end

      def job_durations_by_name_for(workflows, statuses: ['success'])
        workflows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |workflow, result|
          workflow.jobs.each do |job|
            next unless statuses.include?(job['status'])

            duration = workflow.numeric_job_duration_for(job)
            result[job['name']] << duration if duration
          end
        end
      end

      def summary_duration_summary_for(workflows, type, blueprint_workflows:, job_statuses: ['success'])
        durations_by_name = job_durations_by_name_for(workflows, statuses: job_statuses)
        duration_bracket_for(durations_by_name, type, blueprint_workflows:)
      end

      def duration_bracket_for(durations_by_name, type, blueprint_workflows:)
        summary_stage_blueprint_for(blueprint_workflows).map do |job_names|
          entries = job_names.map do |job_name|
            duration = summary_metric_for(durations_by_name[job_name], type)
            {
              formatted_duration: duration ? format_duration(duration) : 'n/a',
              name: job_name,
              numeric_duration: duration,
              status: nil
            }
          end

          longest = longest_stage_duration_for(entries)
          formatted = entries.map { |entry| formatted_stage_entry(entry, longest, highlight_longest: type == :p95) }
          "[#{formatted.join('; ')}]"
        end.join(' -> ')
      end

      def duration_summary_messages_for(total_duration_workflows, job_duration_workflows, blueprint_workflows)
        total_durations = total_duration_workflows.filter_map(&:displayed_total_duration)
        return [] if total_durations.empty?

        [['Fastest', :fastest], ['Slowest', :slowest]].filter_map do |label, type|
          total_duration = summary_metric_for(total_durations, type)
          next unless total_duration

          duration_summary = summary_duration_summary_for(job_duration_workflows, type, blueprint_workflows:)
          BASE_TREE_PREFIX + summary_message_for(
            label, format_duration(total_duration), duration_summary,
            type:, numeric_value: total_duration
          )
        end
      end

      def average_summary_messages_for(successful_workflows, failed_workflows, blueprint_workflows)
        [
          ['Average SUCCESS', successful_workflows, successful_workflows],
          ['Average FAILED', failed_workflows, failed_workflows]
        ].filter_map do |label, total_workflows, job_workflows|
          split_summary_message_for(label, total_workflows, job_workflows, blueprint_workflows:, type: :average)
        end
      end

      def p95_summary_messages_for(successful_workflows, failed_workflows, blueprint_workflows)
        [
          ['P95 SUCCESS', successful_workflows, successful_workflows],
          ['P95 FAILED', failed_workflows, failed_workflows]
        ].filter_map do |label, total_workflows, job_workflows|
          split_summary_message_for(label, total_workflows, job_workflows, blueprint_workflows:, type: :p95)
        end
      end

      def split_summary_message_for(label, total_duration_workflows, job_duration_workflows, blueprint_workflows:,
                                    type:)
        total_duration = summary_metric_for(total_duration_workflows.filter_map(&:displayed_total_duration), type)
        return unless total_duration

        job_statuses = label.end_with?('FAILED') ? ['failed'] : ['success']
        duration_summary = summary_duration_summary_for(
          job_duration_workflows, type, blueprint_workflows:, job_statuses:
        )
        BASE_TREE_PREFIX + summary_message_for(
          label, format_duration(total_duration), duration_summary,
          type:, numeric_value: total_duration
        )
      end

      def chain_duration_summary_messages_for(first_attempt_workflows, blueprint_workflows, prepend_spacing: false)
        successful_chains, failed_chains = first_attempt_workflows.partition(&:eventually_succeeded?)

        messages = %i[fastest slowest].map do |type|
          chain_summary_message_for(type, successful_chains, blueprint_workflows, job_statuses: ['success'])
        end
        messages += %i[average p95].flat_map do |type|
          [
            chain_summary_message_for(type, successful_chains, blueprint_workflows, job_statuses: ['success']),
            chain_summary_message_for(type, failed_chains, blueprint_workflows, job_statuses: ['failed'])
          ]
        end
        messages.compact!
        return [] if messages.empty?

        messages.unshift('') if prepend_spacing
        messages
      end

      def chain_summary_message_for(type, chains, blueprint_workflows, job_statuses:)
        total_duration = summary_metric_for(chains.filter_map(&:chain_total_duration), type)
        return unless total_duration

        durations_by_name = chain_job_durations_by_name_for(chains, statuses: job_statuses)
        bracket = duration_bracket_for(durations_by_name, type, blueprint_workflows:)
        label = chain_summary_label_for(type, job_statuses)
        BASE_TREE_PREFIX + summary_message_for(
          label, format_duration(total_duration), bracket, type:, numeric_value: total_duration
        )
      end

      def chain_summary_label_for(type, job_statuses)
        base = case type
               when :fastest then 'Fastest'
               when :slowest then 'Slowest'
               when :average then "Average #{job_statuses.include?('failed') ? 'FAILED' : 'SUCCESS'}"
               when :p95 then "P95 #{job_statuses.include?('failed') ? 'FAILED' : 'SUCCESS'}"
               end
        "#{base} (incl. reruns)"
      end

      def chain_job_durations_by_name_for(chains, statuses:)
        chains.each_with_object(Hash.new { |h, k| h[k] = [] }) do |chain, result|
          totals = Hash.new(0)
          present = {}
          chain.chain_workflows.each do |workflow|
            workflow.jobs.each do |job|
              next unless statuses.include?(job['status'])

              duration = workflow.numeric_job_duration_for(job)
              next unless duration

              totals[job['name']] += duration
              present[job['name']] = true
            end
          end
          present.each_key { |name| result[name] << totals[name] }
        end
      end

      def cost_summary_message_for(workflows, successful_workflows, blueprint_workflows)
        workflow = aggregate_cost_workflow_for(workflows, successful_workflows)
        return unless workflow

        cost_credits_by_name = job_cost_credits_by_name_for(workflow)
        return if cost_credits_by_name.empty?

        BASE_TREE_PREFIX + summary_message_for(
          'Costs (credits, est.)',
          format_kilo_credits(cost_credits_by_name.values.sum),
          cost_summary_for(blueprint_workflows, cost_credits_by_name)
        )
      end

      def success_rate_summary_messages_for(first_attempt_workflows, blueprint_workflows,
                                            prepend_spacing: false)
        total = first_attempt_workflows.size
        overall_rate = percentage_for(first_attempt_workflows.count(&:eventually_succeeded?), total)
        overall_one_shot = percentage_for(first_attempt_workflows.count { |w| w.status == 'success' }, total)
        overall_flaky = percentage_for(
          first_attempt_workflows.count { |w| w.status != 'success' && w.eventually_succeeded? }, total
        )
        return [] unless overall_rate || overall_one_shot

        messages = []
        messages << '' if prepend_spacing
        messages << rate_message_for(
          'Success Rate', overall_rate, eventual_success_rate_summary_for(first_attempt_workflows, blueprint_workflows:)
        )
        messages << rate_message_for(
          'One-Shot Rate', overall_one_shot,
          summary_success_rate_summary_for(first_attempt_workflows, blueprint_workflows:)
        )
        messages << rate_message_for(
          'Flaky Tests Rate', overall_flaky,
          flaky_rate_summary_for(first_attempt_workflows, blueprint_workflows:), type: :flaky
        )
        messages.compact
      end

      def rate_message_for(name, value, rate_summary, type: nil)
        return unless value

        BASE_TREE_PREFIX + summary_message_for("#{name} (#{@range_label})", value, rate_summary, type:)
      end

      def aggregate_cost_workflow_for(workflows, successful_workflows)
        reference = cost_reference_workflow_for(successful_workflows)
        return unless reference

        durations_by_name = aggregate_job_durations_by_name_for(workflows)
        return if durations_by_name.empty?

        reference.merge(
          'jobs' => reference.jobs.map { |job| job.merge('aggregate_duration' => durations_by_name[job['name']]) }
        )
      end

      def cost_reference_workflow_for(successful_workflows)
        successful_workflows.max_by do |workflow|
          [workflow.counted_job_count, workflow.created_at || Time.at(0).utc]
        end
      end

      def aggregate_job_durations_by_name_for(workflows)
        workflows.each_with_object(Hash.new(0)) do |workflow, result|
          workflow.jobs.each do |job|
            duration = workflow.numeric_job_duration_for(job)
            result[job['name']] += duration if duration
          end
        end
      end

      def job_cost_credits_by_name_for(workflow)
        workflow.jobs.each_with_object({}) do |job, result|
          cost_credits = workflow.numeric_job_cost_credits_for(job)
          result[job['name']] = cost_credits if cost_credits
        end
      end

      def cost_summary_for(blueprint_workflows, cost_credits_by_name)
        summary_stage_blueprint_for(blueprint_workflows).map do |job_names|
          entries = job_names.map do |job_name|
            cost_credits = cost_credits_by_name[job_name]
            {
              formatted_duration: cost_credits ? format_kilo_credits(cost_credits) : 'n/a',
              name: job_name,
              numeric_duration: cost_credits,
              status: nil
            }
          end

          formatted = entries.map { |entry| formatted_stage_entry(entry, nil, highlight_longest: false) }
          "[#{formatted.join('; ')}]"
        end.join(' -> ')
      end

      def summary_success_rates_by_name_for(workflows)
        workflows.each_with_object(Hash.new do |h, k|
          h[k] = { success_count: 0, total_count: 0 }
        end) do |workflow, result|
          workflow.jobs.each do |job|
            next if job['status'] == 'not_run'

            entry = result[job['name']]
            entry[:total_count] += 1
            entry[:success_count] += 1 if job['status'] == 'success'
          end
        end
      end

      def eventual_success_rates_by_name_for(first_attempt_workflows)
        first_attempt_workflows.each_with_object(Hash.new do |h, k|
          h[k] = { success_count: 0, total_count: 0 }
        end) do |workflow, result|
          workflow.eventual_job_outcomes.each do |name, outcome|
            entry = result[name]
            entry[:total_count] += 1
            entry[:success_count] += 1 if outcome[:succeeded]
          end
        end
      end

      def eventual_success_rate_summary_for(first_attempt_workflows, blueprint_workflows: first_attempt_workflows)
        rates_by_name = eventual_success_rates_by_name_for(first_attempt_workflows)
        summary_for_rates(rates_by_name, blueprint_workflows)
      end

      def flaky_rates_by_name_for(first_attempt_workflows)
        first_attempt_workflows.each_with_object(Hash.new do |h, k|
          h[k] = { success_count: 0, total_count: 0 }
        end) do |workflow, result|
          outcomes = workflow.eventual_job_outcomes
          workflow.jobs.each do |job|
            next if job['status'] == 'not_run'

            entry = result[job['name']]
            entry[:total_count] += 1
            recovered = job['status'] != 'success' && outcomes.dig(job['name'], :succeeded)
            entry[:success_count] += 1 if recovered
          end
        end
      end

      def flaky_rate_summary_for(first_attempt_workflows, blueprint_workflows: first_attempt_workflows)
        rates_by_name = flaky_rates_by_name_for(first_attempt_workflows)
        summary_for_rates(rates_by_name, blueprint_workflows, invert: true)
      end

      def summary_success_rate_summary_for(workflows, blueprint_workflows: workflows)
        rates_by_name = summary_success_rates_by_name_for(workflows)
        summary_for_rates(rates_by_name, blueprint_workflows)
      end

      def summary_for_rates(rates_by_name, blueprint_workflows, invert: false)
        rate_values = rates_by_name.values.filter_map do |rates|
          percentage_value_for(percentage_for(rates[:success_count], rates[:total_count]))
        end
        worst_rate = invert ? rate_values.max : rate_values.min

        summary_stage_blueprint_for(blueprint_workflows).map do |job_names|
          entries = job_names.map do |job_name|
            rates = rates_by_name[job_name]
            formatted_rate = percentage_for(rates[:success_count], rates[:total_count])
            { formatted_duration: formatted_rate || 'n/a', name: job_name, numeric_duration: nil, status: nil }
          end

          formatted = entries.map do |entry|
            formatted_stage_entry(entry, nil, highlight_longest: false, worst_percentage: worst_rate, invert:)
          end
          "[#{formatted.join('; ')}]"
        end.join(' -> ')
      end

      def summary_message_for(label, value_text, duration_summary, type: nil, numeric_value: nil)
        formatted_value = value_text.rjust(5)
        formatted_value = colorize_percentage(formatted_value, invert: type == :flaky) if value_text.match?(/\A\d+%\z/)
        formatted_value = colorize_p95_duration(formatted_value, numeric_value) if type == :p95 && numeric_value
        padding = ' ' * [SUMMARY_VALUE_START - label.size, 1].max

        message = "#{label}#{padding}#{formatted_value}"
        message << " #{duration_summary}" unless duration_summary.empty?
        message
      end

      def formatted_stage_entry(entry, longest_duration, highlight_longest: true, worst_percentage: nil, invert: false)
        padded = entry[:formatted_duration].rjust(5)
        padded = colorize(padded, :red) if %w[failed error].include?(entry[:status])
        padded = colorize_percentage(padded, invert:) if entry[:formatted_duration].match?(/\A\d+%\z/)
        if worst_percentage && percentage_value_for(entry[:formatted_duration]) == worst_percentage
          padded = colorize(padded, :bold)
        end
        if highlight_longest && longest_duration &&
           entry[:formatted_duration].match?(/\A\d+:\d{2}\z/) &&
           entry[:numeric_duration] == longest_duration
          padded = colorize(padded, :bold)
        end

        "#{entry[:name]}#{padded}"
      end

      def longest_stage_duration_for(entries)
        durations = entries.filter_map do |entry|
          entry[:numeric_duration] if entry[:formatted_duration].match?(/\A\d+:\d{2}\z/)
        end

        durations.max if durations.size > 1
      end

      def summary_metric_for(values, type)
        return if values.empty?

        case type
        when :fastest then values.min
        when :slowest then values.max
        when :average then (values.sum.to_f / values.size).round
        when :p95 then percentile(values, 0.95)
        else raise ArgumentError, "Unsupported summary type: #{type}"
        end
      end

      def percentile(values, fraction)
        sorted = values.sort
        return if sorted.empty?

        rank = [(sorted.size * fraction).ceil - 1, 0].max
        sorted[rank]
      end

      def percentage_for(success_count, total_count)
        return if total_count.zero?

        "#{((success_count.to_f / total_count) * 100).round}%"
      end

      def percentage_value_for(value)
        value.delete_suffix('%').to_i if value.match?(/\A\d+%\z/)
      end

      def colorize_percentage(value, invert: false)
        percentage = value.delete_suffix('%').to_i
        if invert
          return colorize(value, :green) if percentage.zero?
          return colorize(value, :yellow) if percentage <= 5

          return colorize(value, :red)
        end
        return colorize(value, :green) if percentage == 100
        return colorize(value, :red) if percentage < 95
        return colorize(value, :yellow) if percentage < 100

        value
      end

      def colorize_p95_duration(value, duration)
        return colorize(value, :green) if duration < 10 * 60
        return colorize(value, :yellow) if duration < 15 * 60

        colorize(value, :red)
      end

      def format_kilo_credits(value)
        "#{(value.to_f / 1000).round}k"
      end

      def workflow_url_for(workflow)
        return unless workflow&.pipeline_number && workflow.id

        "#{CIRCLECI_APP_URL}/pipelines/github/#{@org}/#{@project}/#{workflow.pipeline_number}/workflows/#{workflow.id}"
      end

      def parse_time(value)
        Time.iso8601(value).utc if value
      rescue ArgumentError
        nil
      end

      def format_duration(seconds)
        total_seconds = seconds.to_i
        format('%<min>d:%<sec>02d', min: total_seconds / 60, sec: total_seconds % 60)
      end
    end
  end
end
