# frozen_string_literal: true

module TmuxCSwitch
  # Owns the handoff between the project list, fzf, and tmux.
  class Picker
    RESET = "\e[0m"
    FIELD_DELIMITER = "\t"
    PREVIEW_FORMAT = %q(
      #{?window_active,>, } #{window_index}: #{window_name}#{window_flags}  #{window_panes} panes
    ).delete("\n").strip

    def initialize(projects:, gui:, env:, stdout:)
      @projects = projects
      @env = env
      @stdout = stdout
      @tmux = Picker::Tmux.new(env: env)
      @rows = Picker::Rows.new(projects: projects, gui: gui, tmux: @tmux)
    end

    def list_projects(include_hidden_path: false)
      @stdout.puts(project_rows(include_hidden_path: include_hidden_path))
    end

    def kill_project_session(path)
      return false unless path

      system('tmux', 'kill-session', '-t', @projects.session_name(path), out: File::NULL, err: File::NULL)
    end

    def preview_project(path)
      return false unless path

      session = @projects.session_name(path)
      print_preview_header(path, session)

      unless @tmux.session_exists?(session)
        @stdout.puts('no session')
        return true
      end

      exec(*preview_tmux_command(session))
    end

    def select_project(script_path)
      IO.popen(fzf_command(script_path), 'r+') do |io|
        io.write(project_rows(include_hidden_path: true).join("\n"))
        io.write("\n")
        io.close_write
        io.read
      end
    end

    def activate_selection(selection)
      path = selected_path(selection)
      return unless path

      session = @projects.session_name(path)
      session_exists = @tmux.session_exists?(session)
      return activate_within_tmux(session_exists, session, path) if @env.key?('TMUX')

      exec(*activation_command(session_exists, session, path))
    end

    private

    def project_rows(include_hidden_path: false)
      @rows.project_rows(include_hidden_path: include_hidden_path)
    end

    def print_preview_header(path, session)
      @stdout.puts("project  #{@projects.display_path(path)}")
      @stdout.puts("session  #{session}")
      @stdout.puts
    end

    def preview_tmux_command(session)
      ['tmux', 'list-windows', '-t', session, '-F', PREVIEW_FORMAT]
    end

    def fzf_bindings(script_path)
      [
        '--bind',
        'tab:toggle-preview',
        '--bind',
        "ctrl-x:execute-silent(#{script_path} --kill-session {2})+reload(#{script_path} --list-fzf)"
      ]
    end

    def fzf_preview_options(script_path)
      [
        '--preview',
        "#{script_path} --preview {2}",
        '--preview-window',
        'right:60%:hidden'
      ]
    end

    def fzf_command(script_path)
      # FZF shell-quotes numbered placeholders like {2} by default.
      [
        'fzf',
        '--ansi',
        '--header=enter: open/switch | tab: toggle preview | ctrl-x: kill session',
        "--delimiter=#{FIELD_DELIMITER}",
        '--with-nth=4,3',
        *fzf_preview_options(script_path),
        *fzf_bindings(script_path)
      ]
    end

    def selected_path(selection)
      return if selection.nil? || selection.empty?

      fields = selection.split(FIELD_DELIMITER, 3)
      fields[1]
    end

    def activate_within_tmux(session_exists, session, path)
      exit 1 if !session_exists && !system('tmux', 'new-session', '-d', '-s', session, '-c', path)
      exit 1 unless system('tmux', 'switch-client', '-t', session)
    end

    def activation_command(session_exists, session, path)
      return ['tmux', 'attach', '-t', session] if session_exists

      ['tmux', 'new-session', '-s', session, '-c', path]
    end

    # Formats the rows that fzf renders.
    class Rows
      ANSI_COLORS = {
        'black' => "\e[30m",
        'red' => "\e[31m",
        'green' => "\e[32m",
        'yellow' => "\e[33m",
        'blue' => "\e[34m",
        'magenta' => "\e[35m",
        'cyan' => "\e[36m",
        'white' => "\e[37m"
      }.freeze

      def initialize(projects:, gui:, tmux:)
        @projects = projects
        @gui = gui
        @tmux = tmux
      end

      def project_rows(include_hidden_path: false)
        @projects.paths.each_with_index.map do |path, index|
          project_row(index, path, include_hidden_path: include_hidden_path)
        end
      end

      private

      def current_session_marker
        @current_session_marker ||= colorize(marker, current_session_color)
      end

      def session_marker_text
        @session_marker_text ||= colorize(marker, session_color)
      end

      def marker
        @gui.fetch('marker')
      end

      def current_session_color
        ANSI_COLORS.fetch(@gui.fetch('current_session_color'))
      end

      def session_color
        ANSI_COLORS.fetch(@gui.fetch('session_color'))
      end

      def colorize(text, color)
        "#{color}#{text}#{Picker::RESET}"
      end

      def session_marker(session)
        return ' ' unless @tmux.session_listed?(session)
        return current_session_marker if session == @tmux.current_session

        session_marker_text
      end

      def project_row(index, path, include_hidden_path:)
        session = @projects.session_name(path)

        fields = [index]
        fields << @projects.normalize_path(path) if include_hidden_path
        fields << @projects.display_path(path)
        fields << session_marker(session)
        fields.join(Picker::FIELD_DELIMITER)
      end
    end

    # Keeps the picker's tmux calls in one place.
    class Tmux
      def initialize(env:)
        @env = env
      end

      def session_exists?(session)
        system('tmux', 'has-session', '-t', session, out: File::NULL, err: File::NULL)
      end

      def session_listed?(session)
        session_names.include?(session)
      end

      def current_session
        return @current_session if instance_variable_defined?(:@current_session)

        @current_session = @env.key?('TMUX') ? current_session_name : nil
      rescue Errno::ENOENT
        nil
      end

      def current_session_name
        session = IO.popen(
          ['tmux', 'display-message', '-p', '#S'],
          err: File::NULL,
          &:read
        ).to_s.strip
        session.empty? ? nil : session
      end

      private

      def session_names
        @session_names ||= begin
          output = IO.popen(['tmux', 'list-sessions', '-F', '#S'], err: File::NULL, &:read).to_s
          output.lines(chomp: true).to_set
        end
      rescue Errno::ENOENT
        Set.new
      end
    end
  end
end
