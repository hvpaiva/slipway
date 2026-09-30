# frozen_string_literal: true

require 'fileutils'
require_relative 'git_env'

# The repositories the README's examples register, as the first example finds them: hldr is
# clean and was fetched five hours ago; augur has a modified and an untracked file and no
# remote; notes has a commit to push, and its remote has a commit pushed from another clone
# after the fetch two days ago, so only the next fetch shows it. Remotes are bare repositories
# under ~/remotes.
class ReadmeStory
  include GitEnv

  HOUR = 3600
  NAME = 'Highlander'
  EMAIL = 'contact@hvpaiva.dev'
  AUTHOR = { 'GIT_AUTHOR_NAME' => NAME, 'GIT_AUTHOR_EMAIL' => EMAIL,
             'GIT_COMMITTER_NAME' => NAME, 'GIT_COMMITTER_EMAIL' => EMAIL }.freeze

  def initialize(home)
    @home = home
    @now = Time.now
  end

  def build
    hldr
    augur
    notes
  end

  private

  def hldr
    dir = repository('hldr', remote: true)
    commit(dir, 'index.html', "<h1>hvpaiva.dev</h1>\n", 'feat: list posts by year', hours_ago: 32)
    git!(dir, 'push', '-q', '-u', 'origin', 'main')
    fetch(dir, hours_ago: 5)
  end

  def augur
    dir = repository('augur')
    commit(dir, 'history.bash', "augur_history() { fc -ln 1; }\n", 'refactor: split history reader', hours_ago: 11)
    File.write(File.join(dir, 'history.bash'), "augur_history() { fc -ln -500; }\n")
    File.write(File.join(dir, 'rank.bash'), "augur_rank() { sort | uniq -c; }\n")
  end

  def notes
    dir = repository('notes', remote: true)
    commit(dir, 'git.md', "# git\n", 'docs: start the git notes', hours_ago: 60)
    git!(dir, 'push', '-q', '-u', 'origin', 'main')
    fetch(dir, hours_ago: 48)
    commit(dir, 'ruby.md', "# ruby\n", 'docs: start the ruby notes', hours_ago: 20)

    elsewhere = File.join(@home, 'laptop', 'notes')
    git!(@home, 'clone', '-q', '--', remote_path('notes'), elsewhere)
    commit(elsewhere, 'shell.md', "# shell\n", 'docs: start the shell notes', hours_ago: 3)
    git!(elsewhere, 'push', '-q', 'origin', 'main')
  end

  def repository(name, remote: false)
    dir = File.join(@home, 'dev', name)
    FileUtils.mkdir_p(dir)
    git!(dir, 'init', '-q')
    return dir unless remote

    bare = remote_path(name)
    FileUtils.mkdir_p(bare)
    git!(bare, 'init', '-q', '--bare')
    git!(dir, 'remote', 'add', 'origin', bare)
    dir
  end

  def remote_path(name) = File.join(@home, 'remotes', "#{name}.git")

  def commit(dir, file, text, subject, hours_ago:)
    date = "#{ago(hours_ago).to_i} +0000"
    File.write(File.join(dir, file), text)
    git!(dir, 'add', '--', file)
    git!(dir, 'commit', '-q', '-m', subject, env: AUTHOR.merge('GIT_AUTHOR_DATE' => date, 'GIT_COMMITTER_DATE' => date))
  end

  # FETCHED is the age of FETCH_HEAD, so moving the file back dates the fetch.
  def fetch(dir, hours_ago:)
    git!(dir, 'fetch', '-q')
    File.utime(ago(hours_ago), ago(hours_ago), File.join(dir, '.git', 'FETCH_HEAD'))
  end

  def ago(hours) = @now - (hours * HOUR)
end
