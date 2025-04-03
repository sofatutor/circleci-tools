#!/usr/bin/env ruby

def check_early_deploy
  commit_message = `git log --format=%B -n 1 #{ENV['CIRCLE_SHA1']}`
  revert_merge_regex = %r{Merge pull request #[0-9]+.*from #{ENV['CIRCLE_PROJECT_REPONAME']}/revert-(?![0-9]+-revert-)}
  fast_track_regex = /\[ci-fast-track\]/

  if commit_message.match?(revert_merge_regex) || commit_message.match?(fast_track_regex)
    puts 'Early deployment condition met, setting CI_FAST_TRACK variable to 1.'
    File.write(ENV['BASH_ENV'], "export CI_FAST_TRACK=1\n", mode: 'a')
  else
    puts 'No early deployment conditions met, setting CI_FAST_TRACK variable to 0.'
    File.write(ENV['BASH_ENV'], "export CI_FAST_TRACK=0\n", mode: 'a')
  end
end

check_early_deploy if $PROGRAM_NAME == __FILE__
