require 'rails_helper'

require_relative '../../bin/check_early_deploy'

describe 'check_early_deploy' do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('CIRCLE_SHA1').and_return('123456')
    allow(ENV).to receive(:[]).with('CIRCLE_PROJECT_REPONAME').and_return('sofatutor')
    allow(ENV).to receive(:[]).with('BASH_ENV').and_return('test_bash_env')
    allow(File).to receive(:write).with('test_bash_env', any_args, mode: 'a').and_return(nil)
  end

  context 'when commit message contains revert merge information' do
    it 'sets CI_FAST_TRACK to 1' do
      allow_any_instance_of(Object).to receive(:`).with('git log --format=%B -n 1 123456').and_return('Merge pull request #123 from sofatutor/revert-55667-foo-bar')

      expect { check_early_deploy }.to output("Early deployment condition met, setting CI_FAST_TRACK variable to 1.\n").to_stdout
    end
  end

  context 'when commit message contains revert of revert merge information' do
    it 'sets CI_FAST_TRACK to 0' do
      allow_any_instance_of(Object).to receive(:`).with('git log --format=%B -n 1 123456').and_return('Merge pull request #123 from sofatutor/revert-55667-revert-12345-foo-bar-')

      expect { check_early_deploy }.to output("No early deployment conditions met, setting CI_FAST_TRACK variable to 0.\n").to_stdout
    end
  end

  context 'when commit message contains [ci-fast-track]' do
    it 'sets CI_FAST_TRACK to 1' do
      allow_any_instance_of(Object).to receive(:`).with('git log --format=%B -n 1 123456').and_return('[ci-fast-track] Your commit message here')

      expect { check_early_deploy }.to output("Early deployment condition met, setting CI_FAST_TRACK variable to 1.\n").to_stdout
    end
  end

  context 'when commit message does not meet early deployment conditions' do
    it 'sets CI_FAST_TRACK to 0' do
      allow_any_instance_of(Object).to receive(:`).with('git log --format=%B -n 1 123456').and_return('Normal commit message')

      expect { check_early_deploy }.to output("No early deployment conditions met, setting CI_FAST_TRACK variable to 0.\n").to_stdout
    end
  end
end
