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
  spec.files         = Dir.glob('**/*').reject { |f| f.include?('circleci-tools.gemspec') }
  spec.require_paths = ['lib']
  spec.add_development_dependency 'rspec', '~> 3.10'

  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'aws-sdk-cloudwatch'
  spec.add_runtime_dependency 'aws-sdk-cloudwatchlogs'
  spec.add_runtime_dependency 'aws-sdk-s3'
  spec.add_runtime_dependency 'base64'
  spec.add_runtime_dependency 'csv'
  spec.add_runtime_dependency 'date'
  spec.add_runtime_dependency 'faraday'
  spec.add_runtime_dependency 'fileutils'
  spec.add_runtime_dependency 'json'
  spec.add_runtime_dependency 'logger'
  spec.add_runtime_dependency 'rexml'
  spec.add_runtime_dependency 'thor'
  spec.add_runtime_dependency 'time'
  spec.add_runtime_dependency 'tty-progressbar'
  spec.add_runtime_dependency 'tty-prompt'
  spec.add_runtime_dependency 'zlib'
end
