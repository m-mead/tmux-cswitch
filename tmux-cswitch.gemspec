# frozen_string_literal: true

require_relative 'lib/tmux_cswitch/version'

Gem::Specification.new do |spec|
  spec.name = 'tmux-cswitch'
  spec.version = TmuxCSwitch::VERSION
  spec.authors = ['m-mead']
  spec.summary = 'tmux project switcher with fzf'
  spec.required_ruby_version = '>= 3.1.0'
  spec.metadata = { 'rubygems_mfa_required' => 'true' }

  spec.files = Dir[
    'LICENSE',
    'README.md',
    'bin/*',
    'lib/**/*.rb'
  ]
  spec.bindir = 'bin'
  spec.executables = ['tmux-cswitch']
  spec.require_paths = ['lib']
end
