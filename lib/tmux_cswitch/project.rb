# frozen_string_literal: true

require 'digest'
require 'yaml'

module TmuxCSwitch
  # Reads configured project roots and turns them into switchable entries.
  class Project
    CONFIG_PATH = File.expand_path('~/.config/tmux-cswitch/config.yaml')

    def initialize(config:)
      @normalized_paths = {}
      @config = config
    end

    def paths
      @paths ||= each_path.to_a
    end

    def session_name(path)
      named_session = session_names_by_path[path]
      return named_session if named_session

      normalized_path = normalize_path(path)
      parts = normalized_path.split('/').reject(&:empty?)
      "#{session_name_slug(parts.last(1))}-#{short_hash(normalized_path)}"
    end

    def display_path(path)
      normalized = normalize_path(path)
      return '~' if normalized == Dir.home
      return normalized.sub("#{Dir.home}/", '~/') if normalized.start_with?("#{Dir.home}/")

      normalized
    end

    def normalize_path(path)
      @normalized_paths[path] ||= File.realpath(path)
    rescue Errno::ENOENT, Errno::EACCES
      File.expand_path(path)
    end

    private

    def session_names_by_path
      @session_names_by_path ||= build_session_names_by_path
    end

    def build_session_names_by_path
      normalized_parts = paths.to_h do |path|
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

    def session_name_slug(parts)
      parts.map { |part| part.gsub(/[^[:alnum:]_-]/, '-') }.join('__')
    end

    def short_hash(path)
      Digest::SHA1.hexdigest(path)[0, 8]
    end

    def each_path(&)
      return enum_for(__method__) unless block_given?
      return unless File.file?(CONFIG_PATH)

      config_dir = File.dirname(CONFIG_PATH)
      paths_from_config(config_dir).each(&)
    end

    def paths_from_config(config_dir)
      paths = @config.paths.flat_map do |entry|
        paths_for_entry(entry, config_dir)
      end

      paths.sort.uniq
    end

    def paths_for_entry(entry, config_dir)
      root = File.realpath(File.expand_path(entry, config_dir))
      Dir.each_child(root).filter_map do |child|
        next if child.start_with?('.')

        path_for_child(root, child)
      end
    rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR
      warn_invalid_config_path(entry)
      []
    end

    def path_for_child(root, child)
      path = File.join(root, child)
      return unless File.directory?(path)
      return warn_invalid_project_path(path) if path.match?(/[\t\n]/)

      path
    end

    def warn_invalid_config_path(entry)
      warn "invalid path in #{CONFIG_PATH}: #{entry}"
    end

    def warn_invalid_project_path(path)
      warn "invalid project path (contains tab or newline): #{path}"
    end

    # Small wrapper around the YAML config file.
    class Config
      def initialize(path)
        @path = path
      end

      def paths
        load.fetch('paths')
      end

      def gui
        load.fetch('gui')
      end

      private

      def load
        return empty_config unless File.file?(@path)

        data = YAML.safe_load_file(@path, permitted_classes: [], aliases: false)
        validate(data)
      rescue Psych::Exception => e
        warn_invalid_config(e.message)
        empty_config
      end

      def validate(data)
        unless data.is_a?(Hash)
          warn_invalid_config('top-level config must be a mapping')
          return empty_config
        end

        { 'paths' => valid_paths(data['paths']), 'gui' => valid_gui(data['gui']) }
      end

      def valid_paths(paths)
        return [] if paths.nil?
        return paths.grep(String) if paths.is_a?(Array)

        warn_invalid_config("'paths' must be a list")
        []
      end

      def valid_gui(gui)
        return default_gui if gui.nil?

        unless gui.is_a?(Hash)
          warn_invalid_config("'gui' must be a mapping")
          return default_gui
        end

        default_gui.merge(
          'marker' => valid_gui_string(gui, 'marker'),
          'current_session_color' => valid_gui_color(gui, 'current_session_color'),
          'session_color' => valid_gui_color(gui, 'session_color')
        ).compact
      end

      def valid_gui_string(gui, key)
        return unless gui.key?(key)
        return gui[key] if gui[key].is_a?(String)

        warn_invalid_config("'gui.#{key}' must be a string")
        nil
      end

      def valid_gui_color(gui, key)
        value = valid_gui_string(gui, key)
        return if value.nil?
        return value if Picker::Rows::ANSI_COLORS.key?(value)

        warn_invalid_config(
          "'gui.#{key}' must be one of: #{Picker::Rows::ANSI_COLORS.keys.join(', ')}"
        )
        nil
      end

      def default_gui
        {
          'marker' => '+',
          'current_session_color' => 'green',
          'session_color' => 'yellow'
        }
      end

      def empty_config
        { 'paths' => [], 'gui' => default_gui }
      end

      def warn_invalid_config(message)
        warn "invalid config in #{@path}: #{message}"
      end
    end
  end
end
