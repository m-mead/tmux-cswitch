# frozen_string_literal: true

require_relative 'tmux_cswitch/version'
require_relative 'tmux_cswitch/app'
require_relative 'tmux_cswitch/picker'
require_relative 'tmux_cswitch/project'

# Public entrypoint for the gem and the executable.
module TmuxCSwitch
  module_function

  def run(argv:, program_name:, env: ENV, stdout: $stdout)
    App.run(argv: argv, program_name: program_name, env: env, stdout: stdout)
  end
end
