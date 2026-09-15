#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

local_result=$(awk -v direction=left -v sx=100 -v sy=0 -v sw=100 -v sh=100 \
  -v ref_x=150 -v ref_y=75 -f "$repo_dir/lib/local-neighbor.awk" <<'EOF'
%top 0 0 99 49
%bottom 0 50 99 50
%source 100 0 100 100
EOF
)
[ "$local_result" = %bottom ]

remote_result=$(awk -v direction=right -v point_x=49.5 -v point_y=75 \
  -v dx=100 -v dy=0 -v dw=100 -v dh=100 -f "$repo_dir/lib/remote-edge.awk" <<'EOF'
STATE 1 0 0 100 100 100 100
PANE %top 0 0 100 49 100 100
PANE %bottom 0 50 100 50 100 100
EOF
)
[ "$remote_result" = %bottom ]

test_socket=tmux-seamless-remote-protocol-$$
cleanup() { tmux -L "$test_socket" kill-server 2>/dev/null || true; }
trap cleanup EXIT
tmux -L "$test_socket" -f /dev/null new-session -d -s first -x 80 -y 24
tmux -L "$test_socket" new-session -d -s second -x 80 -y 24
tmux -L "$test_socket" split-window -v -t second
tmux -L "$test_socket" run-shell "bash '$repo_dir/tmux-seamless-remote.tmux'"
left_binding=$(tmux -L "$test_socket" list-keys -T root M-Left)
[[ "$left_binding" != *'run-shell -b'* ]]
[[ "$left_binding" = *'bin/navigate'* ]]
socket_path=$(tmux -L "$test_socket" display-message -p -t second '#{socket_path}')
session_id=$(tmux -L "$test_socket" display-message -p -t second '#{session_id}')
protocol_state=$(bash "$repo_dir/bin/remote" "$socket_path" "$session_id" navigate left)
[ "$(sed -n '1{s/ .*//;p;}' <<< "$protocol_state")" = STATE ]
[ "$(rg -c '^PANE ' <<< "$protocol_state")" = 2 ]
top_pane=$(tmux -L "$test_socket" list-panes -t second -F '#{pane_id} #{pane_top}' | \
  sort -nk2 | sed -n '1{s/ .*//;p;}')
navigate_result=$(bash "$repo_dir/bin/remote" "$socket_path" "$session_id" navigate up)
[ "$(sed -n '1p' <<< "$navigate_result")" = MOVED ]
active_pane=$(tmux -L "$test_socket" list-panes -t second -F '#{pane_id} #{pane_active}' | \
  awk '$2 == 1 { print $1 }')
[ "$active_pane" = "$top_pane" ]
navigate_result=$(bash "$repo_dir/bin/remote" "$socket_path" "$session_id" navigate down)
[ "$(sed -n '1p' <<< "$navigate_result")" = MOVED ]
bottom_pane=$(tmux -L "$test_socket" list-panes -t second -F '#{pane_id} #{pane_top}' | \
  sort -nk2 | tail -1 | cut -d' ' -f1)
active_pane=$(tmux -L "$test_socket" list-panes -t second -F '#{pane_id} #{pane_active}' | \
  awk '$2 == 1 { print $1 }')
[ "$active_pane" = "$bottom_pane" ]
enter_result=$(bash "$repo_dir/bin/remote" "$socket_path" "$session_id" enter right 0.5 0.75)
[ "$(sed -n '1p' <<< "$enter_result")" = "SELECTED $bottom_pane" ]

printf 'geometry and protocol tests passed\n'
