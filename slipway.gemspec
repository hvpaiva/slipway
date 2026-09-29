# frozen_string_literal: true

require_relative 'lib/slipway/version'

Gem::Specification.new do |spec|
  spec.name = 'slipway'
  spec.version = Slipway::VERSION
  spec.authors = ['Highlander Paiva']
  spec.email = ['contact@hvpaiva.dev']

  spec.summary = 'A kubectl-style registry for the git repositories on your machine'
  spec.description = 'Slipway keeps a registry of the development projects on your machine and shows ' \
                     'their git state the way kubectl shows a cluster: get, describe, apply, labels, ' \
                     'selectors, groups, table/json/yaml output, shell completion and man pages.'
  spec.homepage = 'https://github.com/hvpaiva/slipway'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'documentation_uri' => 'https://rubydoc.info/gems/slipway',
    'rubygems_mfa_required' => 'true'
  }

  # Only tracked files ship, so the gem has to be built from a git checkout.
  gemspec = File.basename(__FILE__)
  development_only = %w[bin/ test/ .github/ Gemfile Rakefile .rubocop.yml .editorconfig .gitattributes
                        .gitignore .yardopts mise.toml CODE_OF_CONDUCT.md CONTRIBUTING.md SECURITY.md
                        ARCHITECTURE.md]
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject { |f| f == gemspec || f.start_with?(*development_only) }
  end
  spec.bindir = 'exe'
  spec.executables = ['slipway']
  spec.require_paths = ['lib']
end
