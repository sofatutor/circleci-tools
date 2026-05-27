#!/usr/bin/env ruby
# frozen_string_literal: true

# rubocop:disable Metrics/CyclomaticComplexity

require 'json'
require 'net/http'
require 'open3'
require 'uri'

module CheckSkip
  module_function

  GITHUB_API_ACCEPT = 'application/vnd.github+json'
  CIRCLE_API_HOST = 'circleci.com'

  def fetch_last_successful_commit
    org = ENV.fetch('CIRCLE_PROJECT_USERNAME', nil)
    repo = ENV.fetch('CIRCLE_PROJECT_REPONAME', nil)
    branch = ENV.fetch('CIRCLE_BRANCH', nil)
    token = ENV.fetch('CIRCLE_CI_API_TOKEN', nil)

    if [org, repo, branch, token].any? { |v| v.nil? || v.empty? }
      warn '[ERROR] Missing required environment variables (org, repo, branch, or token).'
      return nil
    end

    uri = URI.parse("https://circleci.com/api/v2/project/gh/#{org}/#{repo}/pipeline")
    uri.query = URI.encode_www_form('branch' => branch)

    response = http_get(uri, token)
    return nil if response.nil?

    parsed = JSON.parse(response)

    return nil if parsed['message']

    checked = 0
    max_pipelines = 8

    (parsed['items'] || []).each do |pipeline|
      checked += 1
      break if checked > max_pipelines

      pipeline_id = pipeline['id']
      revision = pipeline.dig('vcs', 'revision')

      next if pipeline_id.nil? || pipeline_id == 'null'
      next if revision.nil? || revision == 'null' || revision.empty?

      workflow_uri = URI.parse("https://circleci.com/api/v2/pipeline/#{pipeline_id}/workflow")
      workflow_body = http_get(workflow_uri, token)
      next if workflow_body.nil?

      workflows = JSON.parse(workflow_body)

      success = (workflows['items'] || []).any? { |w| w['status'] == 'success' }
      return revision if success
    end

    warn "[INFO] No successful pipeline found for branch #{branch}."
    nil
  end

  def http_get(uri, token, headers: {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri.request_uri)
    req['Circle-Token'] = token if token && !token.empty? && uri.host == CIRCLE_API_HOST
    headers.each { |k, v| req[k] = v }
    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      warn "[ERROR] HTTP #{res.code} from #{uri.host}#{uri.request_uri}: #{res.body}"
      return nil
    end
    res.body
  end

  def http_post(uri, token)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.request_uri)
    req['Circle-Token'] = token
    http.request(req)
  end

  def git_commit_available?(commit_sha)
    system('git', 'cat-file', '-e', "#{commit_sha}^{commit}",
           out: File::NULL, err: File::NULL)
  end

  def ensure_commit_available(commit_sha, branch)
    return true if git_commit_available?(commit_sha)

    system('git', 'fetch', 'origin', branch, '--deepen=100',
           out: File::NULL, err: File::NULL) || true
    git_commit_available?(commit_sha)
  end

  def git_changed_files(base_commit, circle_sha1)
    args = ['git', 'diff', '--name-only', base_commit, circle_sha1]
    stdout, stderr, status = Open3.capture3(*args)
    unless status.success?
      warn "[WARN] git command failed: #{args.join(' ')} — #{stderr}"
      return []
    end
    stdout.split("\n").map(&:strip).reject(&:empty?)
  end

  def git_show_changed_files(circle_sha1)
    args = ['git', 'show', '--pretty=', '--name-only', circle_sha1]
    stdout, stderr, status = Open3.capture3(*args)
    unless status.success?
      warn "[WARN] git command failed: #{args.join(' ')} — #{stderr}"
      return []
    end
    stdout.split("\n").map(&:strip).reject(&:empty?)
  end

  def git_rev_parse(ref)
    stdout, _stderr, status = Open3.capture3('git', 'rev-parse', ref)
    return nil unless status.success?

    sha = stdout.strip
    sha.empty? ? nil : sha
  end

  def git_merge_base(base_ref, head_ref)
    stdout, _stderr, status = Open3.capture3('git', 'merge-base', base_ref, head_ref)
    return nil unless status.success?

    sha = stdout.strip
    sha.empty? ? nil : sha
  end

  def cancel_workflow_if_possible(reason)
    puts reason
    token = ENV['CIRCLE_CI_API_TOKEN']
    workflow_id = ENV['CIRCLE_WORKFLOW_ID']
    if token.nil? || token.empty? || workflow_id.nil? || workflow_id.empty?
      puts 'CIRCLE_CI_API_TOKEN or CIRCLE_WORKFLOW_ID not set. Cannot cancel workflow. Exiting with code 0.'
      exit 0
    end

    uri = URI.parse("https://circleci.com/api/v2/workflow/#{workflow_id}/cancel")
    res = http_post(uri, token)
    warn "Workflow cancel HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    puts 'Workflow cancellation requested. Exiting.'
    exit 0
  end

  def parse_pr_base_branch
    pr_url = ENV['CIRCLE_PULL_REQUEST'].to_s
    gh_token = ENV['GITHUB_BOT_TOKEN'].to_s
    gh_token = ENV['GITHUB_TOKEN'].to_s if gh_token.empty?

    return nil if pr_url.empty? || gh_token.empty?
    return nil unless (m = pr_url.match(%r{/pull/(\d+)$}))

    pr_number = m[1]
    owner = ENV['CIRCLE_PROJECT_USERNAME'].to_s
    repo = ENV['CIRCLE_PROJECT_REPONAME'].to_s
    return nil if owner.empty? || repo.empty?

    uri = URI.parse("https://api.github.com/repos/#{owner}/#{repo}/pulls/#{pr_number}")
    body = http_get(uri, nil, headers: { 'Authorization' => "Bearer #{gh_token}", 'Accept' => GITHUB_API_ACCEPT })
    return nil if body.nil?

    parsed = JSON.parse(body)
    base = parsed.dig('base', 'ref').to_s
    base.empty? ? nil : base
  rescue JSON::ParserError
    nil
  end

  def parse_skip_paths_from_env(value)
    return [] if value.nil? || value.strip.empty?

    val = value.strip
    if val.start_with?('[') && val.end_with?(']')
      begin
        parsed = JSON.parse(val)
        return Array(parsed).map(&:to_s).map(&:strip).reject { |s| s.empty? || s.lstrip.start_with?('#') }
      rescue JSON::ParserError
        # fall through
      end
    end

    if val.include?(',')
      return val.split(',').map(&:strip).reject { |s| s.empty? || s.lstrip.start_with?('#') }
    end

    val.split(/\s+/).map(&:strip).reject { |s| s.empty? || s.lstrip.start_with?('#') }
  end

  def read_skip_paths_from_file(path)
    return [] if path.nil? || path.strip.empty?
    return [] unless File.file?(path)

    File.read(path).lines.map(&:chomp).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  rescue Errno::ENOENT, Errno::EACCES
    []
  end

  def rule_has_glob?(rule)
    rule.include?('*') || rule.include?('?') || rule.include?('[')
  end

  def path_matches_rule?(file, rule)
    normalized_file = file.sub(%r{\A\./}, '')
    normalized_rule = rule.sub(%r{\A\./}, '')

    if rule_has_glob?(normalized_rule)
      return File.fnmatch?(normalized_rule, normalized_file, File::FNM_PATHNAME)
    end

    dir_rule = normalized_rule.sub(%r{/\z}, '')
    normalized_file == dir_rule || normalized_file.start_with?("#{dir_rule}/")
  end

  def all_changes_skipped?(files, skip_paths)
    return false if skip_paths.empty?

    files.all? do |file|
      skip_paths.any? { |rule| path_matches_rule?(file, rule) }
    end
  end

  def run
    unless Dir.exist?('.git')
      warn '[ERROR] .git directory not found. Exiting.'
      exit 1
    end

    branch = ENV.fetch('CIRCLE_BRANCH', '')
    circle_sha1 = ENV.fetch('CIRCLE_SHA1', '')

    base_commit = git_rev_parse("#{circle_sha1}~1")
    if base_commit
      puts '[INFO] Using previous commit on branch as base.'
    else
      base_commit = fetch_last_successful_commit
    end

    if base_commit.nil? || base_commit.empty?
      puts '[INFO] No previous successful commit found. Resolving fallback base commit.'

      pr_base_branch = parse_pr_base_branch
      if pr_base_branch && !pr_base_branch.empty?
        puts "[INFO] Using merge-base against PR base branch '#{pr_base_branch}'."
        system('git', 'fetch', 'origin', pr_base_branch, '--deepen=100',
               out: File::NULL, err: File::NULL) ||
          system('git', 'fetch', 'origin', pr_base_branch, out: File::NULL, err: File::NULL) || true
        base_commit = git_merge_base("origin/#{pr_base_branch}", circle_sha1)
      end

      if base_commit.nil? || base_commit.empty?
        base_commit = git_rev_parse("#{circle_sha1}~1")
        puts '[INFO] Falling back to previous commit on branch.' if base_commit
      end

      if base_commit.nil? || base_commit.empty?
        system('git', 'fetch', 'origin', branch, '--deepen=50', out: File::NULL, err: File::NULL) ||
          system('git', 'fetch', 'origin', branch, '--depth=50', out: File::NULL, err: File::NULL) || true
        base_commit = git_rev_parse("origin/#{branch}")
        puts "[INFO] Falling back to origin/#{branch}." if base_commit
      end
    end

    changed_files =
      if base_commit.nil? || base_commit.empty?
        puts '[WARN] Could not determine a reliable base commit; defaulting to current commit file list.'
        git_show_changed_files(circle_sha1)
      elsif !ensure_commit_available(base_commit, branch)
        puts "[WARN] Base commit #{base_commit} unavailable after fetch. Falling back to current commit file list."
        git_show_changed_files(circle_sha1)
      else
        git_changed_files(base_commit, circle_sha1)
      end

    if changed_files.empty?
      cancel_workflow_if_possible('[INFO] No changes detected for this commit. Cancelling workflow.')
    end

    puts 'Change set:'
    puts changed_files.join("\n")

    skip_paths = []
    skip_paths.concat(read_skip_paths_from_file(ENV['CI_SKIP_FILE']))
    skip_paths.concat(parse_skip_paths_from_env(ENV['CI_SKIP_PATHS']))

    if all_changes_skipped?(changed_files, skip_paths)
      if ENV['CI_SKIP_FILE'] && !ENV['CI_SKIP_FILE'].to_s.empty?
        cancel_workflow_if_possible(
          "All changes are within CI_SKIP_FILE (#{ENV['CI_SKIP_FILE']}). Cancelling workflow."
        )
      else
        cancel_workflow_if_possible(
          "All changes are within CI_SKIP_PATHS (#{ENV['CI_SKIP_PATHS']}). Cancelling workflow."
        )
      end
    end

    puts 'Relevant changes found. Continuing build.'
    exit 0
  end
end

CheckSkip.run if $PROGRAM_NAME == __FILE__

# rubocop:enable Metrics/ModuleLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Style/Documentation
