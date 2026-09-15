#!/usr/bin/env bash

# Discover the OpenSSH destination attached to a tmux pane using Linux procfs.
tsr_ssh_target() {
  local pane=$1 tty ssh_pid argument consumes_next=0
  local -a arguments

  [ "$(tmux display-message -p -t "$pane" '#{pane_current_command}')" = ssh ] || return 1
  tty=$(tmux display-message -p -t "$pane" '#{pane_tty}')
  ssh_pid=$(ps -ww -t "$tty" -o pid=,tpgid=,comm= 2>/dev/null | \
    awk '$1 == $2 && $3 == "ssh" { print $1; exit }')
  [ -n "$ssh_pid" ] && [ -r "/proc/$ssh_pid/cmdline" ] || return 1

  readarray -d '' -t arguments < "/proc/$ssh_pid/cmdline"
  for argument in "${arguments[@]:1}"; do
    if [ "$consumes_next" = 1 ]; then
      consumes_next=0
      continue
    fi
    case "$argument" in
      --) continue ;;
      -[BbcDEeFIiJLlmOopQRSWw]) consumes_next=1 ;;
      -*) ;;
      *) printf '%s\n' "$argument"; return ;;
    esac
  done
  return 1
}

# Parse the capability descriptor published by the inner tmux as its terminal
# title. Output: SSH target, encoded helper path, encoded socket path, session.
tsr_peer_for_pane() {
  local pane=$1 target title marker helper socket session remainder
  target=$(tsr_ssh_target "$pane") || return 1
  title=$(tmux display-message -p -t "$pane" '#{pane_title}')
  IFS=: read -r marker helper socket session remainder <<< "$title"

  [ "$marker" = TSR1 ] && [ -z "$remainder" ] || return 1
  [[ "$helper" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  [[ "$socket" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  [[ "$session" =~ ^\$[0-9]+$ ]] || return 1
  printf '%s %s %s %s\n' "$target" "$helper" "$socket" "$session"
}

tsr_ssh_options() {
  local timeout control_dir
  timeout=$(tmux show-option -gqv @seamless-remote-connect-timeout)
  timeout=${timeout:-2}
  control_dir=${XDG_RUNTIME_DIR:-/tmp}/tmux-seamless-remote-$(id -u)
  install -d -m 700 "$control_dir"
  TSR_SSH_OPTIONS=(-o BatchMode=yes -o "ConnectTimeout=$timeout" \
    -o ControlMaster=auto -o ControlPersist=yes -o "ControlPath=$control_dir/%C")
}

tsr_remote_call() {
  local target=$1 helper_token=$2 socket_token=$3 session=$4 mode=$5
  shift 5
  local argument quoted command command_arguments=
  [[ "$helper_token" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  [[ "$socket_token" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  [[ "$session" =~ ^\$[0-9]+$ ]] || return 1
  case "$mode" in
    navigate)
      [ "$#" = 1 ] || return 1
      case "$1" in left|down|up|right) ;; *) return 1 ;; esac
      ;;
    enter)
      [ "$#" = 3 ] || return 1
      case "$1" in left|down|up|right) ;; *) return 1 ;; esac
      [[ "$2" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
      [[ "$3" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
      ;;
    *) return 1 ;;
  esac

  for argument in "$@"; do
    printf -v quoted '%q' "$argument"
    command_arguments+=" $quoted"
  done

  command="helper=\$(printf %s '$helper_token' | base64 -d); socket=\$(printf %s '$socket_token' | base64 -d); [ -r \"\$helper\" ] && bash \"\$helper\" \"\$socket\" '$session' '$mode'$command_arguments"
  tsr_ssh_options
  ssh "${TSR_SSH_OPTIONS[@]}" "$target" "$command" 2>/dev/null
}
