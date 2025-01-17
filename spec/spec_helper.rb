require 'simplecov'
SimpleCov.start

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
