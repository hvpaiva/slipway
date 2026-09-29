# frozen_string_literal: true

module GetRegistry
  # The head commit every fixture repository starts from.
  HEAD = '5bbaee2'
  SHA = '5bbaee2c60e94db1f64d04925d8365eec25d449b'

  def registry(env)
    seed(env,
         manifest('Group', 'work', description: 'Day job'),
         manifest('Project', 'clean', path: repo(env, 'clean'), labels: { 'lang' => 'rust' },
                                      description: 'A clean one'),
         manifest('Project', 'dirty', path: repo(env, 'dirty', 'untracked'), labels: { 'lang' => 'go' }),
         manifest('Project', 'gone', path: repo(env, 'gone', nil)),
         manifest('Project', 'plain', path: repo(env, 'plain', 'plain_dir')),
         manifest('Project', 'ahead', group: 'work', path: repo(env, 'ahead', 'ahead'),
                                      labels: { 'lang' => 'rust', 'tier' => 'api' }),
         manifest('Project', 'detached', group: 'work', path: repo(env, 'detached', 'detached')))
  end
end
