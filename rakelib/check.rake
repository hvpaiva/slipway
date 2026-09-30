# frozen_string_literal: true

require_relative 'support/commits'

desc 'Run what CI runs, except the Ruby and OS matrix and the zsh and fish job (CHECK_OFFLINE=1 skips network checks)'
task check: %w[rubocop lint:shell lint:man lint:spelling lint:workflows lint:links lint:commits
               test:cov test:integration generate:check package:check] do
  if ENV.fetch('CHECK_OFFLINE', '').empty?
    Rake::Task['audit'].invoke
  else
    puts "check: CHECK_OFFLINE is set, so the advisory audit and zizmor's online audits were skipped; CI runs them"
  end
end

namespace :lint do
  desc "Run bin/lint-commits over the commits HEAD adds to #{Commits::BASE}"
  task :commits do
    range, skipped = Commits.branch_range
    if range
      ruby 'bin/lint-commits', range
    else
      puts "lint:commits: #{skipped}, so no commit was linted"
    end
  rescue Commits::Error => e
    abort "lint:commits: #{e.message}"
  end
end
