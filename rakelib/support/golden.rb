# frozen_string_literal: true

module GoldenFixtures
  module_function

  def expected(registry, shells)
    help = command_paths(registry.root).map { File.join('help', "#{[registry.program, *it].join('-')}.txt") }
    completion = shells.map { File.join('completion', "#{registry.program}.#{it}") }
    help + completion
  end

  def command_paths(command, path = [])
    [path, *command.visible_subcommands.flat_map { command_paths(it, [*path, it.name]) }]
  end

  def remove_orphans(root, expected)
    orphans = Dir.glob('**/*', base: root).select { File.file?(File.join(root, it)) } - expected
    orphans.each { File.delete(File.join(root, it)) }
    orphans
  end
end
