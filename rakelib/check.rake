# frozen_string_literal: true

desc 'Run what CI runs, except the Ruby and OS matrix and the zsh and fish job (CHECK_OFFLINE=1 skips audit)'
task check: %w[rubocop lint:shell lint:man test:cov test:integration generate:check package:check] do
  if ENV.fetch('CHECK_OFFLINE', '').empty?
    Rake::Task['audit'].invoke
  else
    puts 'check: CHECK_OFFLINE is set, so the advisory audit was skipped; CI still runs it'
  end
end
