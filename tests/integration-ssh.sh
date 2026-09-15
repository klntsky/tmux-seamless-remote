#!/usr/bin/env bash
set -euo pipefail

ssh_target=${1:?usage: integration-ssh.sh user@host}
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_id=$$
local_socket=tsr-integration-$test_id
remote_a=tsr-integration-a-$test_id
remote_b=tsr-integration-b-$test_id
SSH_TEST=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target")

cleanup() {
  tmux -L "$local_socket" kill-server 2>/dev/null || true
  "${SSH_TEST[@]}" "tmux kill-session -t '$remote_a' 2>/dev/null || true; tmux kill-session -t '$remote_b' 2>/dev/null || true" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

remote_title_format=$("${SSH_TEST[@]}" "tmux show-option -gqv set-titles-string")
case "$remote_title_format" in
  TSR1:*) ;;
  *) printf 'remote tmux has not loaded tmux-seamless-remote\n' >&2; exit 1 ;;
esac

read -r remote_a_id remote_b_id remote_a_bottom remote_b_bottom <<< "$(
  "${SSH_TEST[@]}" \
    "tmux new-session -d -s '$remote_a' -x 60 -y 30; \
     tmux split-window -v -t '$remote_a'; \
     tmux new-session -d -s '$remote_b' -x 60 -y 30; \
     tmux split-window -v -t '$remote_b'; \
     printf '%s %s %s %s\\n' \
       \"\$(tmux display-message -p -t '$remote_a' '#{session_id}')\" \
       \"\$(tmux display-message -p -t '$remote_b' '#{session_id}')\" \
       \"\$(tmux list-panes -t '$remote_a' -F '#{pane_id} #{pane_top}' | sort -nk2 | tail -1 | cut -d' ' -f1)\" \
       \"\$(tmux list-panes -t '$remote_b' -F '#{pane_id} #{pane_top}' | sort -nk2 | tail -1 | cut -d' ' -f1)\""
)"

tmux -L "$local_socket" -f /dev/null new-session -d -s test -x 120 -y 40 \
  "ssh -tt '$ssh_target' tmux attach-session -t '$remote_a'"
left_pane=$(tmux -L "$local_socket" display-message -p '#{pane_id}')
right_pane=$(tmux -L "$local_socket" split-window -h -p 50 -t "$left_pane" -P -F '#{pane_id}' \
  "ssh -tt '$ssh_target' tmux attach-session -t '$remote_b'")
tmux -L "$local_socket" run-shell "bash '$repo_dir/tmux-seamless-remote.tmux'"

for attempt in $(seq 1 50); do
  left_title=$(tmux -L "$local_socket" display-message -p -t "$left_pane" '#{pane_title}')
  right_title=$(tmux -L "$local_socket" display-message -p -t "$right_pane" '#{pane_title}')
  [ "${left_title##*:}" = "$remote_a_id" ] && [ "${right_title##*:}" = "$remote_b_id" ] && break
  sleep 0.1
done
[ "${left_title##*:}" = "$remote_a_id" ]
[ "${right_title##*:}" = "$remote_b_id" ]

"${SSH_TEST[@]}" "tmux select-pane -t '$remote_a_bottom'"
tmux -L "$local_socket" run-shell "bash '$repo_dir/bin/navigate' right '$left_pane'"
active_local=$(tmux -L "$local_socket" list-panes -F '#{pane_id} #{pane_active}' | awk '$2 == 1 { print $1 }')
active_remote=$("${SSH_TEST[@]}" "tmux list-panes -t '$remote_b' -F '#{pane_id} #{pane_active}'" | \
  awk '$2 == 1 { print $1 }')

[ "$active_local" = "$right_pane" ]
[ "$active_remote" = "$remote_b_bottom" ]

# Exercise the native local fast path followed by synchronous peer entry.
remote_b_top=$("${SSH_TEST[@]}" "tmux list-panes -t '$remote_b' -F '#{pane_id} #{pane_top}'" | \
  sort -nk2 | sed -n '1{s/ .*//;p;}')
"${SSH_TEST[@]}" "tmux select-pane -t '$remote_b_top'"
left_bottom=$(tmux -L "$local_socket" split-window -v -t "$left_pane" -P -F '#{pane_id}')
tmux -L "$local_socket" select-pane -t "$left_bottom"
tmux -L "$local_socket" select-pane -R
tmux -L "$local_socket" run-shell "bash '$repo_dir/bin/enter' right '$right_pane'"
active_remote=$("${SSH_TEST[@]}" "tmux list-panes -t '$remote_b' -F '#{pane_id} #{pane_active}'" | \
  awk '$2 == 1 { print $1 }')
[ "$active_remote" = "$remote_b_bottom" ]
printf 'multi-session SSH integration test passed\n'
