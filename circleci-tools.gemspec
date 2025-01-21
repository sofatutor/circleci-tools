require 'pathname'

Gem::Specification.new do |spec|
  spec.name          = 'circleci-tools'
  spec.version       = '0.1.0'
  spec.authors       = ['Manuel Fittko']
  spec.email         = ['manuel.fittko@sofatutor.com']
  spec.summary       = 'CircleCI Tools'
  spec.description   = 'Collection of CircleCI-related utilities under one gem.'
  spec.homepage      = 'https://www.sofatutor.com'
  spec.license       = 'MIT'

  spec.bindir        = 'bin'
  spec.executables   = ['circleci-metrics']
  spec.files         = [
    'bin/circleci-metrics',
    'lib/circleci-tools/api_service.rb',
    'lib/circleci-tools/cloudwatch_metrics_service.rb',
    'lib/circleci-tools/data_aggregator.rb',
    'lib/circleci-tools/job_analyzer.rb',
    'lib/circleci-tools/log_uploader.rb',
    'lib/circleci-tools/retryable.rb',
    'lib/circleci-tools/runner_calculator.rb',
    'lib/circleci-tools/s3_upload_service.rb',
    'lib/circleci-tools/usage_report_service.rb',
    'README.md',
  ]
  spec.require_paths = ['lib']
  spec.add_development_dependency 'rspec', '~> 3.10'

  spec.add_runtime_dependency 'activesupport', '~> 8.0.1'
  spec.add_runtime_dependency 'aws-sdk-cloudwatch', '~> 1.109.0'
  spec.add_runtime_dependency 'aws-sdk-cloudwatchlogs', '~> 1.106.0'
  spec.add_runtime_dependency 'aws-sdk-s3', '~> 1.178.0'
  spec.add_runtime_dependency 'base64', '~> 0.2.0'
  spec.add_runtime_dependency 'csv', '~> 3.3.2'
  spec.add_runtime_dependency 'date', '~> 3.4.1'
  spec.add_runtime_dependency 'faraday', '~> 2.12.2'
  spec.add_runtime_dependency 'fileutils', '~> 1.7.3'
  spec.add_runtime_dependency 'json', '~> 2.9.1'
  spec.add_runtime_dependency 'logger', '~> 1.6.5'
  spec.add_runtime_dependency 'rexml', '~> 3.4.0'
  spec.add_runtime_dependency 'thor', '~> 1.3.2'
  spec.add_runtime_dependency 'time', '~> 0.4.1'
  spec.add_runtime_dependency 'tty-progressbar', '~> 0.18.3'
  spec.add_runtime_dependency 'tty-prompt', '~> 0.23.1'
  spec.add_runtime_dependency 'zlib', '~> 3.2.1'
end
