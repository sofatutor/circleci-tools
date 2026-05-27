# frozen_string_literal: true

require 'benchmark'
require 'optparse'
require 'yaml'

module CircleciTools
  module Kpi
    DEFAULT_ORG = 'sofatutor'
    DEFAULT_BRANCH = 'main'
    DEFAULT_DAYS = 7
    CONFIG_FILE = '~/.circleci/cli.yml'

    DEFAULT_WORKFLOW_NAMES = {
      'sofatutor' => 'build_test_and_coverage_main',
      'sofatutor-kids' => 'build-and-test-main',
      'SPASS' => 'test',
      'cobain' => 'build-and-test'
    }.freeze

    DEFAULT_ALL_BRANCHES_WORKFLOW_NAMES = {
      'sofatutor' => 'build_test_and_coverage',
      'sofatutor-kids' => 'build-and-test'
    }.freeze

    DEFAULT_OPTIONS = {
      org: DEFAULT_ORG,
      workflow: nil,
      branch: DEFAULT_BRANCH,
      days: DEFAULT_DAYS,
      week: nil,
      links: false,
      show_branch: false,
      verbose: false
    }.freeze

    class CLI
      def initialize(argv)
        @argv = argv.dup
      end

      def run
        return puts(usage) if help_requested?

        request = resolved_request
        print_request_context(request)
        loader = build_loader
        show_workflows(loader, request)
      end

      private

      def help_requested?
        %w[help -h --help].include?(@argv.first)
      end

      def resolved_request
        options, project_name = parse_cli
        workflow_name = options.fetch(:workflow).to_s.strip
        branch = options.fetch(:branch)
        project_name = normalize_project_name(project_name)

        if workflow_name.empty?
          workflow_name = if branch.nil?
                            DEFAULT_ALL_BRANCHES_WORKFLOW_NAMES[project_name] || DEFAULT_WORKFLOW_NAMES[project_name]
                          elsif branch == DEFAULT_BRANCH
                            DEFAULT_WORKFLOW_NAMES[project_name]
                          end
        end

        if workflow_name.to_s.empty?
          abort "Please provide a workflow name for project #{colorize(project_name,
                                                                       :yellow)}."
        end

        { project: project_name, **options.merge(workflow: workflow_name) }
      end

      def print_request_context(request)
        puts "Project: #{colorize("#{request.fetch(:org)}/#{request.fetch(:project)}", :yellow)}"
        puts "Workflow: #{colorize(request.fetch(:workflow), :yellow)}"
        puts "Branch: #{colorize(request.fetch(:branch) || '*', :yellow)}"
        puts "Range: #{colorize(requested_range_for(days: request.fetch(:days), week: request[:week]), :yellow)}"
        puts
      end

      def build_loader
        configuration = load_configuration
        client = Client.new(token: configuration.fetch('token'), host: configuration.fetch('host'))
        Loader.new(client:)
      end

      def show_workflows(loader, request)
        print 'loading workflows...'
        workflows, load_duration = load_workflows(loader, request)
        job_count = workflows.sum(&:counted_job_count)
        print("\r#{' ' * 40}\r")
        puts load_message_for(workflows.size, job_count, load_duration)
        puts unless request.fetch(:verbose)

        if workflows.empty?
          puts 'No workflows found.'
          return
        end

        formatter = TerminalFormatter.new(
          org: request.fetch(:org),
          project: request.fetch(:project),
          range_label: requested_success_rate_range_for(days: request.fetch(:days), week: request[:week]),
          links: request.fetch(:links),
          show_branch: request.fetch(:show_branch)
        )

        workflows.each { |workflow| puts formatter.render_workflow(workflow) } if request.fetch(:verbose)

        summary_messages = formatter.summary_messages(workflows)
        return if summary_messages.empty?

        puts if request.fetch(:verbose)
        summary_messages.each { |message| puts message }
      end

      def load_workflows(loader, request)
        workflows = nil
        load_duration = Benchmark.realtime do
          workflows = loader.displayed_workflows(
            org: request.fetch(:org),
            project: request.fetch(:project),
            workflow_name: request.fetch(:workflow),
            branch: request.fetch(:branch),
            range: { days: request.fetch(:days), week: request[:week] }
          )
          workflows = enrich_cost_workflow(loader, workflows, request)
        end

        [workflows, load_duration]
      end

      def enrich_cost_workflow(loader, workflows, request)
        cost_workflow = workflows.select { |w| w.status == 'success' }.max_by do |w|
          [w.counted_job_count, w.created_at || Time.at(0).utc]
        end
        return workflows unless cost_workflow

        workflows.map do |workflow|
          next workflow unless workflow.id == cost_workflow.id

          loader.enrich_jobs_with_parallelism(workflow, org: request.fetch(:org), project: request.fetch(:project))
        end
      end

      def load_message_for(run_count, job_count, load_duration)
        rounded_tenths = (load_duration * 10).round
        formatted_runs = colorize(run_count.to_s, :yellow)
        formatted_jobs = colorize(job_count.to_s, :yellow)
        formatted_duration = colorize(format('%.1f', rounded_tenths / 10.0), :yellow)

        "Loaded #{formatted_runs} #{run_count == 1 ? 'run' : 'runs'} and " \
          "#{formatted_jobs} #{job_count == 1 ? 'job' : 'jobs'} in " \
          "#{formatted_duration} #{rounded_tenths == 10 ? 'second' : 'seconds'}."
      end

      def usage
        build_option_parser(DEFAULT_OPTIONS.dup).to_s
      end

      def build_option_parser(options)
        OptionParser.new do |parser|
          parser.banner = "Usage: #{$PROGRAM_NAME} project [options]"
          define_filter_options(parser, options)
          define_output_options(parser, options)
          parser.on('-h', '--help', 'Show help') { puts parser; exit } # rubocop:disable Style/Semicolon
        end
      end

      def define_filter_options(parser, options)
        parser.on('-d', '--days DAYS', Integer,
                  "Load workflows from the last N days (default: #{DEFAULT_DAYS})") { |v| options[:days] = v }
        parser.on('-W', '--week WEEK', Integer,
                  'Load workflows from ISO calendar week N of the current year (overrides --days)') do |v|
          raise OptionParser::InvalidArgument, TimeWindow.invalid_week_message(v) unless TimeWindow.valid_week?(v)

          options[:week] = v
        end
        parser.on('-o', '--org ORG', String,
                  "CircleCI organization/user (default: #{DEFAULT_ORG})") { |v| options[:org] = v }
        parser.on('-b', '--branch BRANCH', String,
                  "Branch to filter (default: #{DEFAULT_BRANCH})") { |v| options[:branch] = v }
        parser.on('-a', '--all', "Don't filter by branch (overrides --branch)") { options[:branch] = nil }
        parser.on('-w', '--workflow WORKFLOW', String,
                  'Workflow name (inferred for some projects on main or all branches)') { |v| options[:workflow] = v }
      end

      def define_output_options(parser, options)
        parser.on('-l', '--links', 'Append CircleCI links to run rows (implies --verbose)') do
          options[:links] = true
          options[:verbose] = true
        end
        parser.on('-B', '--show-branch', 'Append the branch name to run rows (implies --verbose)') do
          options[:show_branch] = true
          options[:verbose] = true
        end
        parser.on('-v', '--verbose', 'Print the list of runs before aggregates') { options[:verbose] = true }
      end

      def parse_cli
        arguments = @argv.dup
        options = DEFAULT_OPTIONS.dup
        parser = build_option_parser(options)

        parser.permute!(arguments)
        abort "Unexpected arguments: #{arguments.drop(1).join(' ')}" if arguments.size > 1
        if arguments.empty? || arguments.first.to_s.strip.empty?
          abort "Please provide a project (like \"main\" or \"kids\").\n\n#{usage}"
        end

        [options, arguments.first.to_s.strip]
      rescue OptionParser::ParseError => e
        abort "#{e.message}\n#{parser}"
      end

      def normalize_project_name(project_name)
        case project_name
        when 'kids' then 'sofatutor-kids'
        when 'main' then 'sofatutor'
        else project_name
        end
      end

      def requested_range_for(days:, week: nil)
        TimeWindow.label_for(days:, week:)
      end

      def requested_success_rate_range_for(days:, week: nil)
        TimeWindow.short_label_for(days:, week:)
      end

      def load_configuration
        env_token = ENV.values_at('CIRCLE_CI_API_TOKEN', 'CIRCLECI_TOKEN', 'CIRCLE_TOKEN').find do |value|
          value.to_s.strip != ''
        end

        env_token = env_token.to_s.strip
        return { 'host' => DEFAULT_HOST, 'token' => env_token } unless env_token.empty?

        path = File.expand_path(CONFIG_FILE)

        if File.exist?(path)
          config = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
          host = (config['host'] || config[:host] || DEFAULT_HOST).to_s.strip
          token = (config['token'] || config[:token]).to_s.strip

          unless token.empty?
            return {
              'host' => host.empty? ? DEFAULT_HOST : host,
              'token' => token
            }
          end
        end

        example = { host: DEFAULT_HOST, token: '[paste your CircleCI token here]' }.to_yaml
        abort(
          "Please configure a CircleCI token in #{CONFIG_FILE}:" \
          "\n\n#{example}\n…or run the circleci setup command to create it."
        )
      end

      def colorize(text, color)
        Term::ANSIColor.public_send(color, text)
      end
    end
  end
end
