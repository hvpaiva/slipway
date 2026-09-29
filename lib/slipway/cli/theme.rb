# frozen_string_literal: true

module Slipway
  module CLI
    # Maps output roles to SGR parameter strings, following kubecolor's dark and light presets.
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
        dry_run: '36',
        error: '31',
        warning: '33'
      }.freeze

      # The light preset swaps white for black and cyan for blue; every other role is shared.
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

      # Returns the preset called +name+ or raises Slipway::Error for an unknown one.
      def self.fetch(name)
        roles = PRESETS.fetch(name) do
          raise Slipway::Error, "unknown theme #{name.inspect} (known themes: #{NAMES.join(', ')})"
        end
        new(name, roles)
      end

      # The dark preset, used until a theme is chosen.
      def self.default = fetch(DEFAULT_NAME)

      def initialize(name, roles)
        @name = name
        @roles = roles
      end

      # Every role name the theme knows.
      def roles = @roles.keys

      # SGR parameters for a single-valued role, such as "90;3".
      def sgr(role)
        value = @roles.fetch(role)
        raise ArgumentError, "role #{role.inspect} is a list; use sgr_at" if value.is_a?(Array)

        value
      end

      # SGR parameters for the +index+-th entry of a list role, wrapping around the list.
      def sgr_at(role, index)
        values = Array(@roles.fetch(role))
        values[index % values.size]
      end
    end
  end
end
