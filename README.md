# tmux-seamless-remote

Prefix-free pane navigation across nested tmux sessions over SSH.
Stop doing mental math calculating the right prefix combination.

`Alt` + **arrow** switches focused pane both inside the current tmux and across an SSH boundary
(when the tmux on the other side also has this plugin installed).

The other machine must be accessible by SSH in batch mode (without a passphrase prompt) in order for
the signaling session to be established.

## Install

Install the plugin on both the local and remote hosts.

With TPM:

```tmux
set -g @plugin klntsky/tmux-seamless-remote
```

Without TPM, clone it and source its entrypoint:

```tmux
run-shell "bash ~/.tmux/plugins/tmux-seamless-remote/tmux-seamless-remote.tmux"
```

Then reload tmux on both hosts.

## Configuration

To override the keys before loading the plugin:

```tmux
set -g @seamless-remote-left-key  M-h
set -g @seamless-remote-down-key  M-j
set -g @seamless-remote-up-key    M-k
set -g @seamless-remote-right-key M-l
```

Bindings are local to each tmux server and technically they may not match (although that defeats the purpose of using this software somewhat).

## Requirements and limitations

- tmux with pane geometry formats, Bash, awk, OpenSSH, and Linux `/proc` for
  automatic target discovery. The plugin is tested with tmux 3.4 and 3.6.
- The plugin owns tmux's `set-titles` and `set-titles-string` options because
  the terminal title is its peer-discovery channel.
- The local process must be able to open a separate batch-mode SSH connection
  to the same destination. Existing SSH agent and `~/.ssh/config` settings are
  honored; password prompts are never opened by a key binding.
- The exact server socket and session are addressed for every operation. The
  plugin intentionally falls back to normal local navigation when it cannot
  prove that a compatible peer exists.

See also: [ARCHITECTURE.md](ARCHITECTURE.md).
