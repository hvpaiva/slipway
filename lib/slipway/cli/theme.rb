# frozen_string_literal: true

module Slipway
  module CLI
    # The presets follow kubecolor's dark and light themes.
    class Theme
      # Roles whose value is a list are cycled by an index (column or nesting depth).
      DARK = {
        table_header: '1',
        table_columns: %w[37 36],
        describe_keys: %w[96 36],
        string: '93',
        number: '35',
        boolean_true: '32',
        boolean_false: '31',
        none: '90;3',
        status_success: '32',
        status_warning: '33',
        status_danger: '31',
        muted: '90;3',
        help_header: '1',
        help_flag: '36',
        help_command: '32',
        help_comment: '90;3',
        apply_created: '32',
        apply_configured: '33',
        apply_unchanged: '35',
        create_created: '32',
        delete_deleted: '31',
        label_labeled: '32',
        label_unlabeled: '33',
        label_not_labeled: '90;3',
        result_changed: '32',
        result_unchanged: '35',
        result_skipped: '33',
        result_paused: '90;3',
        result_denied: '31',
        result_failed: '31',
        dry_run: '36',
        error: '31',
        warning: '33'
      }.freeze

      # White becomes black, cyan blue and bright yellow plain yellow, to read on a light background.
      LIGHT = DARK.merge(
        table_columns: %w[30 34],
        describe_keys: %w[94 34],
        string: '33',
        help_flag: '34',
        dry_run: '34'
      ).freeze

      PRESETS = { 'dark' => DARK, 'light' => LIGHT }.freeze
      NAMES = PRESETS.keys.freeze
      DEFAULT_NAME = 'dark'

      attr_reader :name

      # Callers check `name` against NAMES first, so an unknown name here is a bug.
      def self.fetch(name)
        new(name, PRESETS.fetch(name))
      end

      def self.default = fetch(DEFAULT_NAME)

      def initialize(name, roles)
        @name = name
        @roles = roles
      end

      def sgr(role)
        value = @roles.fetch(role)
        raise ArgumentError, "role #{role.inspect} is a list; use sgr_at" if value.is_a?(Array)

        value
      end

      def sgr_at(role, index)
        values = Array(@roles.fetch(role))
        values[index % values.size]
      end
    end
  end
end
