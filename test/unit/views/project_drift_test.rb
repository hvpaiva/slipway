# frozen_string_literal: true

require 'test_helper'

class ViewsProjectDriftTest < Minitest::Test
  include OutputHelper
  include PlanHelper

  VIEW = Slipway::Views::Project
  ORIGIN = 'https://bot:s3cret@forge.test/hldr.git'
  URL = 'git@github.com:hvpaiva/hldr.git'

  def test_the_wide_row_joins_every_drift_type_and_blocker_in_order
    inspection = inspect_project(BEHIND.with(unstaged: 1), origin: ORIGIN, remote: URL)

    assert_equal 'Remote,Behind,Dirty', VIEW.row(inspection, now: CommandsHelper::NOW, wide: true).last
    assert_nil VIEW.row(inspect_project(CLEAN), now: CommandsHelper::NOW, wide: true).last
  end

  def test_describe_ends_with_one_line_per_item_keyed_by_its_word
    inspection = inspect_project(BEHIND.with(unstaged: 1), origin: ORIGIN, remote: URL)

    assert render(VIEW.describe(inspection, now: CommandsHelper::NOW)).end_with?(<<~TEXT)
      Drift:
        Remote:  origin is https://***@forge.test/hldr.git, manifest says #{URL}; sync never changes a remote
        Behind:  3 commits behind origin/main
        Dirty:   1 unstaged; sync fast-forwards only a tree without staged or unstaged changes
    TEXT
  end

  def test_the_object_lists_the_drift_redacted_and_plain
    inspection = inspect_project(BEHIND.with(upstream: "origin/ma\e[8min"), origin: ORIGIN, remote: URL)

    assert_equal [{ 'type' => 'Remote', 'blocker' => false,
                    'message' => "origin is https://***@forge.test/hldr.git, manifest says #{URL}; sync never " \
                                 'changes a remote' },
                  { 'type' => 'Behind', 'blocker' => false,
                    'message' => '3 commits behind origin/ma^[[8min; sync will fast-forward' }],
                 VIEW.object(inspection).dig('status', 'drift')
  end

  private

  def inspect_project(status, origin: nil, **spec)
    directory = Slipway::Paths.expand(PATH, home: @home)
    FileUtils.mkdir_p(directory)
    @git.add(directory, status:, commit: COMMIT, remote: origin)
    @inspector.examine(Slipway::Project.new(name: 'hldr', path: PATH, **spec))
  end

  def render(entries) = Slipway::Output::Describe.new(plain_context).render(entries)
end
