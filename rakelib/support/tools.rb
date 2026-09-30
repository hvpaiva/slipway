# frozen_string_literal: true

# The programs the rake tasks run besides Ruby and git. mise.toml pins some at the versions CI
# runs, and bin/setup installs those through mise; the rest come from the system's package
# manager.
module Tools
  MISE_TOML = File.expand_path('../../mise.toml', __dir__)
  TABLE = /\A\[(?<name>[^\]]+)\]\s*\z/
  ENTRY = /\A(?<tool>[a-z][a-z0-9-]*)\s*=\s*"(?<version>[^"]+)"/

  module_function

  # The [tools] table of mise.toml as { tool => version }. Ruby's standard library has no TOML
  # parser, and the table holds plain string versions, which is all this reads.
  def pinned(path = MISE_TOML)
    table = nil
    File.foreach(path, chomp: true).each_with_object({}) do |line, tools|
      if (header = TABLE.match(line))
        table = header[:name]
      elsif table == 'tools' && (entry = ENTRY.match(line))
        tools[entry[:tool]] = entry[:version]
      end
    end
  end

  # mise installs a tool without putting it on PATH until the shell activates mise, and then
  # mise install answers that it is already installed, so that case needs its own advice.
  def missing(tool, pinned = self.pinned, installed_by_mise: pinned.key?(tool) && mise_which?(tool))
    if installed_by_mise
      return "#{tool} is installed by mise but not on PATH; activate mise in your shell (mise activate --help)"
    end

    install = if pinned.key?(tool)
                "the version mise.toml pins with: mise install #{tool}"
              else
                'it with your package manager (pacman, apt or brew)'
              end
    "#{tool} is not installed; install #{install}"
  end

  def mise_which?(tool) = system('mise', 'which', tool, out: File::NULL, err: File::NULL) || false
end
