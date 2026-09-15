#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
navigator="$plugin_dir/bin/navigate"
enterer="$plugin_dir/bin/enter"
remote_helper="$plugin_dir/bin/remote"

encode_title_field() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

option_or_default() {
  local value
  value=$(tmux show-option -gqv "$1")
  printf '%s\n' "${value:-$2}"
}

# Publish an exact server and session identity to a containing tmux. The outer
# server records this terminal title as the SSH pane's #{pane_title}.
helper_token=$(encode_title_field "$remote_helper")
socket_token=$(encode_title_field "$(tmux display-message -p '#{socket_path}')")
tmux set-option -g set-titles on
tmux set-option -g set-titles-string "TSR1:$helper_token:$socket_token:#{session_id}"
tmux set-option -gu @seamless-remote-command 2>/dev/null || true

left_key=$(option_or_default @seamless-remote-left-key M-Left)
down_key=$(option_or_default @seamless-remote-down-key M-Down)
up_key=$(option_or_default @seamless-remote-up-key M-Up)
right_key=$(option_or_default @seamless-remote-right-key M-Right)

peer_format='#{&&:#{==:#{pane_current_command},ssh},#{m:TSR1:*,#{pane_title}}}'

bind_navigation() {
  local key=$1 direction=$2 select=$3
  local remote_navigation="run-shell \"bash '$navigator' $direction #{pane_id}\""
  local enter_remote="run-shell \"bash '$enterer' $direction #{pane_id}\""
  local local_navigation

  # Move with tmux itself, then coordinate only if the selected destination
  # advertises a compatible nested tmux.
  local_navigation="select-pane $select ; if-shell -F '$peer_format' { $enter_remote }"
  tmux bind-key -n "$key" if-shell -F "$peer_format" "$remote_navigation" "$local_navigation"
}

bind_navigation "$left_key" left -L
bind_navigation "$down_key" down -D
bind_navigation "$up_key" up -U
bind_navigation "$right_key" right -R
