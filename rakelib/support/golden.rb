# frozen_string_literal: true

# The golden fixture files the registry calls for today, relative to test/fixtures/golden:
# one help page per visible command and one script per shell. Anything else is an orphan.
module GoldenFixtures
  module_function

  def expected(registry, shells)
    help = command_paths(registry.root).map { File.join('help', "#{[registry.program, *it].join('-')}.txt") }
    completion = shells.map { File.join('completion', "#{registry.program}.#{it}") }
    help + completion
  end

  # Every command path, the root first and groups before their children.
  def command_paths(command, path = [])
    [path, *command.visible_subcommands.flat_map { command_paths(it, [*path, it.name]) }]
  end

  # Removes the files under +root+ that +expected+ does not list and returns their paths.
  def remove_orphans(root, expected)
    orphans = Dir.glob('**/*', base: root).select { File.file?(File.join(root, it)) } - expected
    orphans.each { File.delete(File.join(root, it)) }
    orphans
  end
end
