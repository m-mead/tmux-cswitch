# frozen_string_literal: true

require 'digest'
require 'shellwords'
require 'yaml'

# Core module
module TmuxCSwitch
  CONFIG_PATH = File.expand_path('~/.config/tmux-cswitch/config.yaml')

  RESET = "\e[0m"
  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  MARKER = '+'
  FIELD_DELIMITER = "\t"
  PREVIEW_FORMAT = %q(
    #{?window_active,>, } #{window_index}: #{window_name}#{window_flags}  #{window_panes} panes
  ).delete("\n").strip

  module_function

  def run(argv:, program_name:, env: ENV, stdout: $stdout)
    @env = env
    @stdout = stdout
    @project_paths = project_paths
    @session_names_by_path = build_session_names_by_path

    command = argv.shift
    ensure_dependencies!

    case command
    when '--list'
      list_projects
    when '--list-fzf'
      list_projects(include_hidden_path: true)
    when '--kill-session'
      exit(kill_project_session(argv.shift) ? 0 : 1)
    when '--preview'
      exit(preview_project(argv.shift) ? 0 : 1)
    else
      exit 1 unless File.file?(CONFIG_PATH)

      script_path = Shellwords.escape(File.expand_path(program_name))
      activate_selection(select_project(script_path))
    end
  end

  def ensure_dependencies!
    %w[tmux fzf].each do |command|
      next if @env.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
        path = File.join(directory, command)
        File.file?(path) && File.executable?(path)
      end

      warn "#{command} is required"
      exit 1
    end
  end

  def normalize_path(path)
    normalized_paths[path] ||= File.realpath(path)
  rescue Errno::ENOENT, Errno::EACCES
    File.expand_path(path)
  end

  def normalized_paths
    @normalized_paths ||= {}
  end

  def config
    @config ||= load_config
  end

  def empty_config
    { 'paths' => [] }
  end

  def load_config
    return empty_config unless File.file?(CONFIG_PATH)

    data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [], aliases: false)
    validate_config(data)
  rescue Psych::Exception => e
    warn_invalid_config(e.message)
    empty_config
  end

  def validate_config(data)
    unless data.is_a?(Hash)
      warn_invalid_config('top-level config must be a mapping')
      return empty_config
    end

    { 'paths' => valid_config_paths(data['paths']) }
  end

  def valid_config_paths(paths)
    return [] if paths.nil?
    return paths.grep(String) if paths.is_a?(Array)

    warn_invalid_config("'paths' must be a list")
    []
  end

  def session_name_slug(parts)
    parts.map { |part| part.gsub(/[^[:alnum:]_-]/, '-') }.join('__')
  end

  def short_hash(path)
    Digest::SHA1.hexdigest(path)[0, 8]
  end

  def project_paths
    @project_paths ||= each_project_path.to_a
  end

  def session_names_by_path
    @session_names_by_path ||= build_session_names_by_path
  end

  def build_session_names_by_path
    normalized_parts = project_paths.to_h do |path|
      [path, normalize_path(path).split('/').reject(&:empty?)]
    end

    normalized_parts.each_with_object({}) do |(path, parts), names|
      names[path] = unique_session_name(path, parts, normalized_parts)
    end
  end

  def unique_session_name(path, parts, normalized_parts)
    1.upto(parts.length) do |count|
      candidate = session_name_slug(parts.last(count))
      next if candidate.empty?
      next if session_name_conflict?(path, candidate, count, normalized_parts)

      return candidate
    end

    "#{session_name_slug(parts)}-#{short_hash(normalize_path(path))}"
  end

  def session_name_conflict?(path, candidate, count, normalized_parts)
    normalized_parts.any? do |other_path, other_parts|
      other_path != path && session_name_slug(other_parts.last(count)) == candidate
    end
  end

  def session_name(path)
    session_names_by_path[path] || begin
      normalized = normalize_path(path)
      parts = normalized.split('/').reject(&:empty?)
      "#{session_name_slug(parts.last(1))}-#{short_hash(normalized)}"
    end
  end

  def display_path(path)
    normalized = normalize_path(path)
    return '~' if normalized == Dir.home
    return normalized.sub("#{Dir.home}/", '~/') if normalized.start_with?("#{Dir.home}/")

    normalized
  end

  def warn_invalid_config_path(entry)
    warn "invalid path in #{CONFIG_PATH}: #{entry}"
  end

  def warn_invalid_config(message)
    warn "invalid config in #{CONFIG_PATH}: #{message}"
  end

  def warn_invalid_project_path(path)
    warn "invalid project path (contains tab or newline): #{path}"
  end

  def each_project_path(&)
    return enum_for(__method__) unless block_given?
    return unless File.file?(CONFIG_PATH)

    config_dir = File.dirname(CONFIG_PATH)
    project_paths_from_config(config_dir).each(&)
  end

  def project_paths_from_config(config_dir)
    config.fetch('paths', []).flat_map do |entry|
      project_paths_for_entry(entry, config_dir)
    end
          .sort
          .uniq
  end

  def project_paths_for_entry(entry, config_dir)
    root = File.realpath(File.expand_path(entry, config_dir))
    Dir.each_child(root).filter_map do |child|
      next if child.start_with?('.')

      project_path_for_child(root, child)
    end
  rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR
    warn_invalid_config_path(entry)
    []
  end

  def project_path_for_child(root, child)
    path = File.join(root, child)
    return unless File.directory?(path)
    return warn_invalid_project_path(path) if path.match?(/[\t\n]/)

    path
  end

  def tmux_session_exists?(session)
    system('tmux', 'has-session', '-t', session, out: File::NULL, err: File::NULL)
  end

  def tmux_session_listed?(session)
    tmux_session_names.include?(session)
  end

  def tmux_session_names
    @tmux_session_names ||= begin
      output = IO.popen(['tmux', 'list-sessions', '-F', '#S'], err: File::NULL, &:read).to_s
      output.lines(chomp: true).to_set
    end
  rescue Errno::ENOENT
    Set.new
  end

  def current_tmux_session
    @current_tmux_session ||= begin
      if @env.key?('TMUX')
        session = IO.popen(
          ['tmux', 'display-message', '-p', '#S'],
          err: File::NULL,
          &:read
        ).to_s.strip
        session.empty? ? nil : session
      end
    rescue Errno::ENOENT
      nil
    end
  end

  def colorize(text, color)
    "#{color}#{text}#{RESET}"
  end

  def current_session_marker
    @current_session_marker ||= colorize(MARKER, GREEN)
  end

  def session_marker_text
    @session_marker_text ||= colorize(MARKER, YELLOW)
  end

  def session_marker(session)
    return ' ' unless tmux_session_listed?(session)
    return current_session_marker if session == current_tmux_session

    session_marker_text
  end

  def project_row(index, path, include_hidden_path: false)
    session = session_name(path)

    # FZF carries the real path in a hidden column so activation uses the canonical path.
    fields = [index]
    fields << normalize_path(path) if include_hidden_path
    fields << display_path(path)
    fields << session_marker(session)
    fields.join(FIELD_DELIMITER)
  end

  def project_rows(include_hidden_path: false)
    project_paths.each_with_index.map do |path, index|
      project_row(index, path, include_hidden_path: include_hidden_path)
    end
  end

  def list_projects(include_hidden_path: false)
    @stdout.puts(project_rows(include_hidden_path: include_hidden_path))
  end

  def kill_project_session(path)
    return false unless path

    system('tmux', 'kill-session', '-t', session_name(path), out: File::NULL, err: File::NULL)
  end

  def print_preview_header(path, session)
    @stdout.puts("project  #{display_path(path)}")
    @stdout.puts("session  #{session}")
    @stdout.puts
  end

  def preview_project(path)
    return false unless path

    session = session_name(path)
    print_preview_header(path, session)

    unless tmux_session_exists?(session)
      @stdout.puts('no session')
      return true
    end

    exec(*preview_tmux_command(session))
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

  def select_project(script_path)
    IO.popen(fzf_command(script_path), 'r+') do |io|
      io.write(project_rows(include_hidden_path: true).join("\n"))
      io.write("\n")
      io.close_write
      io.read
    end
  end

  def selected_path(selection)
    return if selection.nil? || selection.empty?

    _, path, = selection.split(FIELD_DELIMITER, 3)
    path
  end

  def activate_within_tmux(session_exists, session, path)
    exit 1 if !session_exists && !system('tmux', 'new-session', '-d', '-s', session, '-c', path)
    exit 1 unless system('tmux', 'switch-client', '-t', session)
  end

  def activation_command(session_exists, session, path)
    return ['tmux', 'attach', '-t', session] if session_exists

    ['tmux', 'new-session', '-s', session, '-c', path]
  end

  def activate_selection(selection)
    path = selected_path(selection)
    return unless path

    session = session_name(path)
    session_exists = tmux_session_exists?(session)
    return activate_within_tmux(session_exists, session, path) if @env.key?('TMUX')

    exec(*activation_command(session_exists, session, path))
  end
end
