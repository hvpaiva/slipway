# frozen_string_literal: true

require_relative 'names'
require_relative 'labels'
require_relative 'resources'
require_relative 'git/branch_name'
require_relative 'git/url'

module Slipway
  # The fields of each kind of manifest. The manifest reader takes its closed set of fields, their
  # defaults and the words of its refusals from here.
  module Schema
    STRING = 'string'
    BOOLEAN = 'boolean'
    OBJECT = 'Object'
    LABEL_MAP = 'map[string]string'
    # What a refusal says a value of each type has to be.
    NOUNS = { STRING => 'a string', BOOLEAN => 'a boolean', OBJECT => 'a mapping', LABEL_MAP => 'a mapping' }.freeze

    # `type` is the word kubectl explain prints between angle brackets. `rule` completes a sentence
    # that starts with the field, the way a refusal quotes it; `enum` closes the field to a set of
    # words and makes the rule when none is given. An object's `fields` are its children in the
    # order a manifest writes them, and the object is required when one of them is.
    Field = Data.define(:name, :type, :description, :required, :default, :enum, :rule, :fields) do
      def initialize(name:, type:, description:, required: false, default: nil, enum: nil, rule: nil, fields: [])
        super(name:, type:, description:, required: required || fields.any?(&:required), default:, enum:,
              rule: rule || (enum && "must be #{enum.join(' or ')}"), fields:)
      end

      def field(name) = fields.find { it.name == name }

      # nil when a name on the way is not a field.
      def dig(*names) = names.reduce(self) { |field, name| field&.field(name) }

      # The description followed by the rule as a sentence of its own.
      def meaning = [description, rule && "#{rule[0].upcase}#{rule[1..]}."].compact.join(' ')
    end

    NAME_RULE = "must be #{Names::RULE}".freeze
    LABELS_FIELD = Field.new(name: 'labels', type: LABEL_MAP,
                             description: 'Key and value pairs that a label selector (-l) matches.',
                             rule: "keys must be #{Labels::KEY_RULE}; values must be #{Labels::VALUE_RULE}")
    TIMESTAMP_FIELD = Field.new(name: 'creationTimestamp', type: STRING, rule: 'must be an RFC 3339 timestamp',
                                description: 'When the resource was created, in UTC. slipway sets it on ' \
                                             'creation; written by hand, it has to be quoted.')
    KIND_DESCRIPTION = 'The kind of resource the manifest describes.'
    private_constant :NAME_RULE, :LABELS_FIELD, :TIMESTAMP_FIELD, :KIND_DESCRIPTION

    PROJECT = Field.new(
      name: Resources::PROJECTS.title, type: OBJECT,
      description: 'A registered git repository: where it is on this machine and where it is expected to be, as ' \
                   'the remote, the branch and a commit to hold it at.',
      fields: [
        Field.new(name: 'kind', type: STRING, required: true, enum: [Resources::PROJECTS.title],
                  description: KIND_DESCRIPTION),
        Field.new(
          name: 'metadata', type: OBJECT,
          description: 'Identifies the project: its name and group, its labels, and when it was created.',
          fields: [
            Field.new(name: 'name', type: STRING, required: true, rule: NAME_RULE,
                      description: 'The name of the project, unique within its group.'),
            Field.new(name: 'group', type: STRING, rule: NAME_RULE,
                      description: 'The group the project belongs to; every group but default has to be created ' \
                                   'first. When it is left out, the project goes to the group in effect: -n, then ' \
                                   'SLIPWAY_GROUP, then the group key, then default.'),
            LABELS_FIELD, TIMESTAMP_FIELD
          ]
        ),
        Field.new(
          name: 'spec', type: OBJECT, description: 'Where the repository is, and the state it is expected to be in.',
          fields: [
            Field.new(name: 'path', type: STRING, required: true, rule: 'must not be empty',
                      description: 'The directory of the repository: an absolute path, or one starting with ~/, ' \
                                   'which is expanded against HOME when used so that the manifest means the same ' \
                                   'on every machine. A relative path is reported as Missing.'),
            Field.new(name: 'description', type: STRING, description: 'What the project is, in free text.'),
            Field.new(name: 'remote', type: STRING, rule: "must be #{Git::Url::RULE}",
                      description: 'The URL the origin remote is expected to have; diff reports another one as ' \
                                   'Remote drift, and no command changes a remote. A password, or any user name ' \
                                   'over http and https, where it often carries a token, is refused; use a ' \
                                   'credential helper.'),
            Field.new(name: 'branch', type: STRING, rule: "must be #{Git::BranchName::RULE}",
                      description: 'The branch expected to be checked out; diff reports another one as Branch ' \
                                   'drift, and no command switches branches.'),
            Field.new(name: 'revision', type: STRING,
                      rule: 'must be a full object name, 40 or 64 lowercase hexadecimal characters',
                      description: 'The commit the project is held at, named in full because an abbreviation can ' \
                                   'become ambiguous. sync fast-forwards the branch up to it instead of the ' \
                                   'upstream, never past it and never back to it. rollout undo writes it and ' \
                                   'rollout unpin removes it.'),
            Field.new(name: 'syncPolicy', type: STRING, enum: SyncPolicy::ALL, default: SyncPolicy::FAST_FORWARD,
                      description: 'What sync may do to the repository: FastForward lets it fast-forward the ' \
                                   'checked-out branch, and FetchOnly lets it fetch only.'),
            Field.new(name: 'paused', type: BOOLEAN, default: false,
                      description: 'When true, fetch and sync leave the project alone: they report it as ' \
                                   'paused and run no git command there. rollout pause sets it and rollout ' \
                                   'resume removes it.')
          ]
        )
      ]
    )

    GROUP = Field.new(
      name: Resources::GROUPS.title, type: OBJECT,
      description: 'A namespace that holds projects, the way a Kubernetes namespace holds pods. Deleting a group ' \
                   'removes the registrations of its projects.',
      fields: [
        Field.new(name: 'kind', type: STRING, required: true, enum: [Resources::GROUPS.title],
                  description: KIND_DESCRIPTION),
        Field.new(
          name: 'metadata', type: OBJECT,
          description: 'Identifies the group: its name, its labels, and when it was created.',
          fields: [
            Field.new(name: 'name', type: STRING, required: true, rule: NAME_RULE,
                      description: 'The name of the group, unique in the registry.'),
            LABELS_FIELD, TIMESTAMP_FIELD
          ]
        ),
        Field.new(name: 'spec', type: OBJECT, description: 'What the group is for.',
                  fields: [Field.new(name: 'description', type: STRING,
                                     description: 'What the group holds, in free text.')])
      ]
    )

    KINDS = [PROJECT, GROUP].to_h { [it.name, it] }.freeze
  end
end
