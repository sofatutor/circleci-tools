require 'simplecov'
SimpleCov.start

$LOAD_PATH.unshift(File.expand_path('../lib/circleci-tools', __dir__))
Dir.glob(File.expand_path('../lib/circleci-tools/**/*.rb', __dir__)).each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.disable_monkey_patching!
  config.warnings = true
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
