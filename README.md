# tmux-seamless-remote

Prefix-free pane navigation across nested tmux sessions over SSH.
Stop doing mental math calculating the right prefix combinations.

`Alt` + **arrow** switches focused pane both inside the current tmux and across an SSH boundary
(when the tmux on the other side also has this plugin installed).

The other machine must be accessible by SSH in batch mode (without a passphrase prompt) in order for
the signaling session to be established.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the protocol design, environmental
assumptions, trust model, and fallback contract.

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

The remote installation advertises its exact tmux server socket, session ID,
and helper through the terminal title. The outer tmux records that descriptor
on its SSH pane and probes it using noninteractive SSH. If the destination
cannot be discovered, SSH is unavailable, or the title does not advertise a
compatible peer, navigation stays local without displaying an error.

The first remote transition may pay SSH connection setup latency. Further
transitions reuse a private SSH control connection indefinitely by default.
Remote transitions are synchronous so keys typed immediately afterward are
delivered only after the destination pane is focused. Ordinary local moves use
tmux's native pane selection and do not invoke SSH or a shell helper.

## Configuration

To override the keys before loading the plugin:

```tmux
set -g @seamless-remote-left-key  M-h
set -g @seamless-remote-down-key  M-j
set -g @seamless-remote-up-key    M-k
set -g @seamless-remote-right-key M-l
```

Bindings are local to each tmux server and technically they may not match (although that defeats the purpose of using this software somewhat).

SSH destinations are automatically extracted from the foreground OpenSSH
process on Linux. `mosh` is not supported.

Each SSH pane carries its own exact remote socket and session ID, so several
SSH panes may point at different sessions or different tmux servers on the same
host without configuration. Change the probe timeout with
`@seamless-remote-connect-timeout` (default: 2 seconds).

SSH masters persist without an idle timeout to avoid navigation latency. Their
control sockets live in a mode-0700 per-user runtime directory.

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

## Test

```sh
./tests/geometry.sh
```

Run the disposable two-session integration test against a host where the
plugin is loaded:

```sh
./tests/integration-ssh.sh user@example.com
```
