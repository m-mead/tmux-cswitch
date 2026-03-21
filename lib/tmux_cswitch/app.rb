# frozen_string_literal: true

require 'shellwords'

module TmuxCSwitch
  # Turns CLI arguments into the picker actions.
  class App
    LIST_COMMAND = '--list'
    LIST_FZF_COMMAND = '--list-fzf'
    KILL_SESSION_COMMAND = '--kill-session'
    PREVIEW_COMMAND = '--preview'

    def self.run(...)
      new(...).run
    end

    def initialize(argv:, program_name:, env:, stdout:)
      @argv = argv.dup
      @program_name = program_name
      @env = env
      @stdout = stdout
    end

    def run
      command = @argv.shift
      ensure_dependencies!
      execute(command)
    end

    private

    def execute(command)
      case command
      when LIST_COMMAND
        list_projects
      when LIST_FZF_COMMAND
        list_projects_for_fzf
      else
        execute_picker_command(command)
      end
    end

    def execute_picker_command(command)
      case command
      when KILL_SESSION_COMMAND
        exit_for(picker.kill_project_session(@argv.shift))
      when PREVIEW_COMMAND
        exit_for(picker.preview_project(@argv.shift))
      else
        launch_picker
      end
    end

    def list_projects
      picker.list_projects
    end

    def list_projects_for_fzf
      picker.list_projects(include_hidden_path: true)
    end

    def exit_for(success)
      exit(success ? 0 : 1)
    end

    def launch_picker
      exit 1 unless File.file?(Project::CONFIG_PATH)

      picker.activate_selection(picker.select_project(script_path))
    end

    def ensure_dependencies!
      %w[tmux fzf].each do |command|
        next if command_available?(command)

        warn "#{command} is required"
        exit 1
      end
    end

    def command_available?(command)
      path_entries = @env.fetch('PATH', '').split(File::PATH_SEPARATOR)

      path_entries.any? do |directory|
        path = File.join(directory, command)
        File.file?(path) && File.executable?(path)
      end
    end

    def picker
      @picker ||= Picker.new(projects: projects, env: @env, stdout: @stdout)
    end

    def projects
      @projects ||= Project.new
    end

    def script_path
      Shellwords.escape(File.expand_path(@program_name))
    end
  end
end
