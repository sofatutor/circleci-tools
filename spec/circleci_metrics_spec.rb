require 'spec_helper'
require 'open3'

RSpec.describe 'circleci-metrics' do
  it 'executes successfully' do
    stdout, stderr, status = Open3.capture3('bin/circleci-metrics')
    expect(status.success?).to be true
    expect(stderr).to be_empty
  end
end
