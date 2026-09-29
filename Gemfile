# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# rake and minitest load with the Rakefile, so they stay outside the groups.
gem 'minitest', '~> 6.0'
gem 'rake', '~> 13.4'

group :development do
  gem 'bundler-audit', '~> 0.9', require: false
  gem 'irb'
  gem 'rubocop', '~> 1.91', require: false
  gem 'rubocop-minitest', '~> 0.40', require: false
  gem 'rubocop-performance', '~> 1.27', require: false
  gem 'rubocop-rake', '~> 0.7', require: false
  gem 'yard', '~> 0.9', require: false
end

group :test do
  gem 'simplecov', '~> 1.3', require: false
end
