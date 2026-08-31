#!/usr/bin/env ruby
# frozen_string_literal: true

# Decides whether the current commit is CI-irrelevant and, if so, stops the run.
#
# Skip rules come from CI_SKIP_FILE (a gitignore-style file, one rule per line)
# and/or CI_SKIP_PATHS (comma-, whitespace- or JSON-array-separated). Every
# changed file must match at least one rule for the run to be skipped.
#
# How the run is stopped is chosen with CI_SKIP_ACTION:
#   cancel (default) - cancel the whole workflow through the CircleCI API. Use
#                      when this step lives inside a job that other jobs
#                      `require:`, so halting it would let them run anyway.
#   halt             - end THIS job early and green via `circleci-agent step
#                      halt`. Use when this step lives in a gate job that nothing
#                      depends on (e.g. a setup job that would otherwise submit a
#                      continuation config).
#
# Exits 0 in every non-fatal case: "do not skip" must never fail the build.
# Runs as plain `ruby`, without bundler or ActiveSupport.

require 'json'
require 'net/http'
require 'open3'
require 'uri'

class CheckSkip
  GITHUB_API_ACCEPT = 'application/vnd.github+json'
  CIRCLE_API_HOST = 'circleci.com'
  FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
  DEFAULT_ACTION = 'cancel'

  def self.run
    new.run
  end

  def run
    unless Dir.exist?('.git')
      warn '[ERROR] .git directory not found. Exiting.'
      exit 1
    end

    files = changed_files
    skip!('[INFO] No changes detected for this commit. Skipping tests.') if files.empty?

    puts 'Change set:'
    puts files.join("\n")
    skip!(skip_reason) if all_skipped?(files, skip_paths)

    puts 'Relevant changes found. Continuing build.'
    exit 0
  end

  def path_matches?(file, rule)
    file = file.delete_prefix('./')
    rule = rule.delete_prefix('./')
    return glob_match?(file, rule) if glob?(rule)

    dir = rule.delete_suffix('/')
    file == dir || file.start_with?("#{dir}/")
  end

  def all_skipped?(files, rules)
    return false if rules.empty?

    files.all? { |file| rules.any? { |rule| path_matches?(file, rule) } }
  end

  def skip_paths_from_file(path)
    return [] if missing?(path) || !File.file?(path)

    File.read(path).lines.map { |line| line.chomp.strip }.reject { |line| skip_line?(line) }
  rescue Errno::ENOENT, Errno::EACCES
    []
  end

  def skip_paths_from_env(value)
    return [] if missing?(value)

    val = value.strip
    return parsed_json_paths(val) if val.start_with?('[') && val.end_with?(']')

    split_paths(val)
  end

  private

  def changed_files
    sha = ENV.fetch('CIRCLE_SHA1', '')
    base = resolve_base(sha)
    if missing?(base)
      puts '[WARN] Could not determine a reliable base commit; defaulting to current commit file list.'
      git_names('show', '--pretty=', '--name-only', sha)
    elsif !ensure_commit?(base)
      puts "[WARN] Base commit #{base} unavailable after fetch. Falling back to current commit file list."
      git_names('show', '--pretty=', '--name-only', sha)
    else
      git_names('diff', '--name-only', base, sha)
    end
  end

  def resolve_base(sha)
    parent = git_sha('rev-parse', "#{sha}~1")
    if parent
      puts '[INFO] Using previous commit on branch as base.'
      return parent
    end

    successful = last_successful_commit
    return successful unless missing?(successful)

    puts '[INFO] No previous successful commit found. Resolving fallback base commit.'
    fallback_base(sha)
  end

  def fallback_base(sha)
    merged = pr_merge_base(sha)
    return merged unless missing?(merged)

    parent = git_sha('rev-parse', "#{sha}~1")
    if parent
      puts '[INFO] Falling back to previous commit on branch.'
      return parent
    end

    origin_branch_tip
  end

  def pr_merge_base(sha)
    branch = pr_base_branch
    return if missing?(branch)

    puts "[INFO] Using merge-base against PR base branch '#{branch}'."
    git_fetch(branch, '--deepen=100') || git_fetch(branch)
    git_sha('merge-base', "origin/#{branch}", sha)
  end

  def origin_branch_tip
    branch = ENV.fetch('CIRCLE_BRANCH', '')
    git_fetch(branch, '--deepen=50') || git_fetch(branch, '--depth=50')
    origin = git_sha('rev-parse', "origin/#{branch}")
    puts "[INFO] Falling back to origin/#{branch}." if origin
    origin
  end

  def last_successful_commit
    org, repo, branch, token = circle_project
    return if [org, repo, branch, token].any? { |value| missing?(value) }

    uri = URI.parse("https://circleci.com/api/v2/project/gh/#{org}/#{repo}/pipeline")
    uri.query = URI.encode_www_form('branch' => branch)
    body = http_get(uri, token: token)
    return if body.nil?

    parsed = JSON.parse(body)
    return if parsed['message']

    find_successful_revision(parsed['items'] || [], token, branch)
  end

  def circle_project
    org = ENV.fetch('CIRCLE_PROJECT_USERNAME', nil)
    repo = ENV.fetch('CIRCLE_PROJECT_REPONAME', nil)
    branch = ENV.fetch('CIRCLE_BRANCH', nil)
    token = ENV.fetch('CIRCLE_CI_API_TOKEN', nil)
    if [org, repo, branch, token].any? { |value| missing?(value) }
      warn '[ERROR] Missing required environment variables (org, repo, branch, or token).'
    end
    [org, repo, branch, token]
  end

  def find_successful_revision(pipelines, token, branch)
    pipelines.first(8).each do |pipeline|
      revision = successful_revision(pipeline, token)
      return revision if revision
    end
    warn "[INFO] No successful pipeline found for branch #{branch}."
    nil
  end

  def successful_revision(pipeline, token)
    pipeline_id = pipeline['id']
    revision = pipeline.dig('vcs', 'revision')
    return if unusable?(pipeline_id) || unusable?(revision)

    uri = URI.parse("https://circleci.com/api/v2/pipeline/#{pipeline_id}/workflow")
    body = http_get(uri, token: token)
    return if body.nil?

    workflows = JSON.parse(body)
    revision if (workflows['items'] || []).any? { |workflow| workflow['status'] == 'success' }
  end

  def pr_base_branch
    pr_url = ENV['CIRCLE_PULL_REQUEST'].to_s
    token = github_token
    owner = ENV['CIRCLE_PROJECT_USERNAME'].to_s
    repo = ENV['CIRCLE_PROJECT_REPONAME'].to_s
    match = pr_url.match(%r{/pull/(\d+)$})
    return if pr_url.empty? || token.empty? || owner.empty? || repo.empty? || match.nil?

    uri = URI.parse("https://api.github.com/repos/#{owner}/#{repo}/pulls/#{match[1]}")
    body = http_get(uri, headers: { 'Authorization' => "Bearer #{token}", 'Accept' => GITHUB_API_ACCEPT })
    return if body.nil?

    base = JSON.parse(body).dig('base', 'ref').to_s
    base unless base.empty?
  rescue JSON::ParserError
    nil
  end

  def github_token
    token = ENV['GITHUB_BOT_TOKEN'].to_s
    token.empty? ? ENV['GITHUB_TOKEN'].to_s : token
  end

  def skip_paths
    skip_paths_from_file(ENV.fetch('CI_SKIP_FILE', nil)) + skip_paths_from_env(ENV.fetch('CI_SKIP_PATHS', nil))
  end

  def parsed_json_paths(val)
    Array(JSON.parse(val)).map { |item| item.to_s.strip }.reject { |line| skip_line?(line) }
  rescue JSON::ParserError
    split_paths(val)
  end

  def split_paths(val)
    parts = val.include?(',') ? val.split(',') : val.split(/\s+/)
    parts.map(&:strip).reject { |line| skip_line?(line) }
  end

  def skip_reason
    file = ENV['CI_SKIP_FILE'].to_s
    if file.empty?
      "All changes are within CI_SKIP_PATHS (#{ENV.fetch('CI_SKIP_PATHS', nil)}). Skipping tests."
    else
      "All changes are within CI_SKIP_FILE (#{file}). Skipping tests."
    end
  end

  # Stop the run. Never raises and never exits non-zero: if the chosen action is
  # unavailable the build simply continues, which is the safe direction.
  def skip!(reason)
    puts reason
    case ENV.fetch('CI_SKIP_ACTION', DEFAULT_ACTION)
    when 'halt' then halt_job
    else cancel_workflow_if_possible
    end
    exit 0
  end

  # Ends THIS job early with a green status. Remaining steps do not run, so a
  # setup job halted here never submits its continuation config.
  def halt_job
    puts 'Halting this job (green); no further steps in it will run.'
    return if system('circleci-agent', 'step', 'halt')

    warn '[WARN] circleci-agent unavailable; cannot halt. Continuing.'
  end

  def cancel_workflow_if_possible
    token = ENV['CIRCLE_CI_API_TOKEN'].to_s
    workflow_id = ENV['CIRCLE_WORKFLOW_ID'].to_s
    if token.empty? || workflow_id.empty?
      puts 'CIRCLE_CI_API_TOKEN or CIRCLE_WORKFLOW_ID not set. Cannot cancel workflow.'
      return
    end

    uri = URI.parse("https://circleci.com/api/v2/workflow/#{workflow_id}/cancel")
    res = http_post(uri, token)
    warn "Workflow cancel HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    puts 'Workflow cancellation requested.'
  end

  def glob?(rule)
    rule.match?(/[*?\[{]/)
  end

  # FNM_PATHNAME keeps `*` from crossing `/`, so `*.md` only matches the repo
  # root. Patterns without a slash also match against the basename (gitignore).
  def glob_match?(file, rule)
    return true if File.fnmatch?(rule, file, FNMATCH_FLAGS)
    return false if rule.include?('/')

    File.fnmatch?(rule, File.basename(file), FNMATCH_FLAGS)
  end

  def ensure_commit?(sha)
    return true if git_available?(sha)

    git_fetch(ENV.fetch('CIRCLE_BRANCH', ''), '--deepen=100')
    git_available?(sha)
  end

  def git_available?(sha)
    system('git', 'cat-file', '-e', "#{sha}^{commit}", out: File::NULL, err: File::NULL)
  end

  def git_fetch(branch, *flags)
    system('git', 'fetch', 'origin', branch, *flags, out: File::NULL, err: File::NULL)
  end

  def git_sha(*)
    stdout, _stderr, status = Open3.capture3('git', *)
    sha = stdout.strip
    status.success? && !sha.empty? ? sha : nil
  end

  def git_names(*)
    stdout, stderr, status = Open3.capture3('git', *)
    unless status.success?
      warn "[WARN] git command failed — #{stderr}"
      return []
    end
    stdout.split("\n").map(&:strip).reject(&:empty?)
  end

  def http_get(uri, token: nil, headers: {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri.request_uri)
    req['Circle-Token'] = token if uri.host == CIRCLE_API_HOST && token.to_s != ''
    headers.each { |key, value| req[key] = value }
    res = http.request(req)
    return res.body if res.is_a?(Net::HTTPSuccess)

    warn "[ERROR] HTTP #{res.code} from #{uri.host}#{uri.request_uri}: #{res.body}"
    nil
  end

  def http_post(uri, token)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.request_uri)
    req['Circle-Token'] = token
    http.request(req)
  end

  def skip_line?(line)
    line.empty? || line.lstrip.start_with?('#')
  end

  def missing?(value)
    value.nil? || value.to_s.empty?
  end

  def unusable?(value)
    missing?(value) || value == 'null'
  end
end

CheckSkip.run if $PROGRAM_NAME == __FILE__
