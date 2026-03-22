# tmux-cswitch

[![CI](https://github.com/m-mead/tmux-cswitch/actions/workflows/lint.yml/badge.svg)](https://github.com/m-mead/tmux-cswitch/actions/workflows/lint.yml)
[![Ruby 3.1+](https://img.shields.io/badge/Ruby-3.1%2B-CC342D.svg)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/m-mead/tmux-cswitch/blob/main/LICENSE)

`tmux-cswitch` is an opinionated `tmux` + `fzf` client switcher.

<img width="1488" height="982" alt="image" src="https://github.com/user-attachments/assets/9588d929-5d0b-4aad-be69-47e9431455ae" />

## Features

- Configurable base paths
- Stable session names (with automatic collision handling) based on project paths
- Visible markers for the current session and other active sessions
- Keybindings to toggle previews and kill sessions

## Requirements

- [Ruby 3.1+](https://www.ruby-lang.org)
- [tmux](https://github.com/tmux/tmux)
- [fzf](https://github.com/junegunn/fzf)

## Installation

```sh
git clone https://github.com/m-mead/tmux-cswitch.git
cd tmux-cswitch
export PATH=$PATH:$PWD/bin
```

## Configuration

`tmux-cswitch` reads its configuration from a file.
The default file location is `~/.config/tmux-cswitch/config.yaml` but can be overridden by setting `TMUXCSWITCH_CONFIG`.

**Sample**
```yaml
paths:
  - ~/projects
  - ~/notes

# Colors are ANSI: black, red, green, yellow, blue, magenta, cyan, white
gui:
  marker: "+"
  current_session_color: green
  session_color: yellow
```

Each configured root in `paths` is resolved and expanded into its immediate child directories; each child is treated as a selectable project.

## Usage

Run:

```sh
bin/tmux-cswitch
```

Inside the picker:
- `enter` switches to or creates the selected project session
- `tab` toggles the preview pane
- `ctrl-x` kills the selected project session

If a session already exists, `tmux-cswitch` switches to it; otherwise, it creates one rooted at the selected path.

## Session Naming

Session names are formed by using the last path component and optionally adding previous path components, joined with `__`, if there is a name collision.
If the full path is exhausted and there is still a conflict, then a unique hash is appended.

## Preview

The picker preview shows:
- Project path
- Generated session name
- Current `tmux` windows for that session, when it exists

## Limitations

- Project paths containing tab characters or newlines are not supported.
- The configuration file does not handle paths with environment variables.

## Inspiration

This tool is inspired by ThePrimeagen's [tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer).

## License

MIT. See [LICENSE](LICENSE).
