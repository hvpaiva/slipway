# frozen_string_literal: true

require 'test_helper'

class ViewsGroupTest < Minitest::Test
  include OutputHelper

  NOW = CommandsHelper::NOW
  GROUP = Slipway::Group.new(name: 'work', labels: { 'team' => 'core' }, created_at: CommandsHelper::CREATED,
                             description: 'Day job')

  def test_headers_add_the_description_when_wide_and_labels_last
    assert_equal %w[NAME PROJECTS AGE], Slipway::Views::Group.headers
    assert_equal %w[NAME PROJECTS AGE DESCRIPTION], Slipway::Views::Group.headers(wide: true)
    assert_equal %w[NAME PROJECTS AGE LABELS], Slipway::Views::Group.headers(labels: true)
    assert_equal %w[NAME PROJECTS AGE DESCRIPTION LABELS], Slipway::Views::Group.headers(wide: true, labels: true)
  end

  def test_row_counts_projects_and_shows_the_age
    assert_equal %w[work 3 3h], Slipway::Views::Group.row(GROUP, count: 3, now: NOW)
    assert_equal ['work', '0', '3h', 'Day job'], Slipway::Views::Group.row(GROUP, count: 0, now: NOW, wide: true)
    assert_equal ['bare', '0', nil, nil],
                 Slipway::Views::Group.row(Slipway::Group.new(name: 'bare'), count: 0, now: NOW, wide: true)
  end

  def test_row_ends_with_the_labels_in_the_form_kubectl_prints
    labeled = GROUP.with(labels: { 'team' => 'core', 'app' => 'web' })

    assert_equal %w[work 3 3h app=web,team=core], Slipway::Views::Group.row(labeled, count: 3, now: NOW, labels: true)
    assert_equal ['work', '3', '3h', 'Day job', 'app=web,team=core'],
                 Slipway::Views::Group.row(labeled, count: 3, now: NOW, wide: true, labels: true)
    assert_equal ['bare', '0', nil, nil],
                 Slipway::Views::Group.row(Slipway::Group.new(name: 'bare'), count: 0, now: NOW, labels: true)
  end

  def test_describe_lists_the_manifest_and_the_project_count
    expected = <<~TEXT
      Name:         work
      Labels:       team=core
      Created:      2026-09-29T09:00:00Z
      Age:          3h
      Description:  Day job
      Projects:     2
    TEXT

    assert_equal expected, render(Slipway::Views::Group.describe(GROUP, count: 2, now: NOW))
  end

  def test_describe_shows_none_for_missing_fields
    rendered = render(Slipway::Views::Group.describe(Slipway::Group.new(name: 'bare'), count: 0, now: NOW))

    assert_equal "Name:         bare\nLabels:       <none>\nCreated:      <none>\nAge:          <none>\n" \
                 "Description:  <none>\nProjects:     0\n", rendered
  end

  def test_object_merges_the_manifest_with_the_project_count
    expected = GROUP.to_manifest.merge('status' => { 'projects' => 2 })

    assert_equal expected, Slipway::Views::Group.object(GROUP, count: 2)
  end

  private

  def render(entries) = Slipway::Output::Describe.new(plain_context).render(entries)
end
