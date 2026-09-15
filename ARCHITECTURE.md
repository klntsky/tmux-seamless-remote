# Architecture

## Goal

`tmux-seamless-remote` treats local and SSH-hosted tmux layouts as one
directional navigation graph. A transition preserves the focused pane's
relative position instead of using either tmux server's focus history.

The implementation is optimistic. Remote coordination is used only when the
SSH pane advertises a compatible peer and the peer answers successfully.
Otherwise navigation remains local and no error is shown to the user.

## Components

- `tmux-seamless-remote.tmux` installs local bindings and publishes this tmux
  server's peer descriptor.
- `bin/navigate` orchestrates one directional transition.
- `lib/peer.sh` discovers SSH destinations, parses peer descriptors, and owns
  the SSH transport.
- `bin/remote` performs operations against one explicitly addressed remote
  tmux socket and session.
- `lib/local-neighbor.awk` and `lib/remote-edge.awk` contain geometry selection
  without SSH or tmux lifecycle concerns.

Bindings and protocol commands are intentionally separate. A binding turns a
local key into a semantic direction (`left`, `down`, `up`, or `right`). Peers
exchange only that direction. Local and remote key bindings do not need to
match.

## Peer identity and protocol

Every configured tmux server enables `set-titles` and publishes a descriptor
with this shape:

```text
TSR1:<base64-helper-path>:<base64-socket-path>:<session-id>
```

`TSR1` is the protocol version. The helper and socket paths are encoded so the
field delimiter cannot occur inside them. `#{session_id}` is expanded by tmux
for the particular client producing the title.

When a remote tmux client is inside an SSH pane, its title travels through SSH
and is recorded by the containing tmux as that pane's `#{pane_title}`. This
gives the parent an exact tuple:

```text
SSH destination + remote tmux socket + remote session ID
```

No session is selected by name, attachment count, or recent activity. Separate
SSH panes may address different sessions on the same server, and non-default
tmux sockets are supported.

The remote helper accepts the socket and session on every request. It verifies
that the socket exists, that the session belongs to that server, and that a
selected pane belongs to the addressed session.

Supported operations are:

- `navigate <direction>`: move within the exact remote session when possible;
  otherwise return the edge state and geometry in the same request.
- `enter <direction> <x> <y>`: choose and select the aligned edge pane using a
  normalized reference point in the remote window.

## Navigation flow

When the source is an advertised peer, `bin/navigate`:

1. Resolves the source pane and its geometry.
2. Checks whether the source is a compatible SSH/tmux peer.
3. Asks the remote helper to navigate; if it moves within the remote layout,
   stops.
4. If the remote pane is at its edge, maps the center of that remote pane into
   the containing local SSH pane.
5. Chooses the nearest local pane in the requested direction, using the mapped
   perpendicular coordinate instead of focus history.
6. If the destination is another compatible SSH/tmux peer, maps the coordinate
   into its remote layout and selects the aligned pane on the entering edge.
7. Selects the local destination pane.

This also covers a direct transition from a pane in remote session A to a pane
in remote session B.

For an ordinary source pane, `bin/navigate` computes the geometry-aware local
neighbor directly. This intentionally avoids tmux's focus-history choice when
several panes are candidates in one direction. It performs no SSH operation
unless the selected neighbor is an advertised peer.

## SSH assumptions

### Destination discovery

Automatic discovery assumes:

- The client host is Linux and exposes readable `/proc/<pid>/cmdline`.
- The foreground process is OpenSSH and is reported as `ssh` by both tmux and
  `ps`.
- The `ssh` process is the foreground process-group leader for the pane's TTY.
- The command line follows ordinary OpenSSH option ordering, with the first
  non-option argument being the destination.

`mosh` is not supported. `autossh`, wrappers, nested launch scripts, non-Linux
clients, and restricted procfs environments are also outside automatic
discovery and are treated as ordinary local panes.

Only the destination token is reused. Inline options from the interactive
command—such as `-p`, `-i`, `-J`, `-F`, and `-o`—are not copied to the probe.
Connection-critical settings therefore need to be available through the
destination's SSH configuration, agent, or equivalent ambient configuration.

### Separate control connection

The plugin cannot issue tmux commands through the interactive SSH channel. It
opens a separate SSH connection to the discovered destination with:

- `BatchMode=yes`
- a configurable connect timeout, defaulting to two seconds
- `ControlMaster=auto`
- `ControlPersist=yes`
- a hashed `%C` control socket under a mode-0700 per-user runtime directory

This assumes:

- Authentication succeeds without a password, OTP, host-key confirmation, or
  other interactive prompt.
- The SSH server permits another connection and ordinary command execution.
- Host-key state is already established.
- The destination resolves to the same account and host as the interactive
  connection.

The master connection has no idle expiry. It ends on explicit SSH master
shutdown, connection failure, runtime-directory cleanup, logout where the
runtime directory is removed, or process termination.

### Remote command environment

The remote noninteractive shell must:

- Find `tmux`, `bash`, and `base64` through its noninteractive `PATH`.
- Access the advertised helper file and tmux socket as the same Unix user.
- Avoid writing unrelated data to stdout before the helper protocol response.

Diagnostic stderr is suppressed during optimistic probing. A malformed or
noisy response is treated as an unavailable peer.

## tmux and terminal assumptions

- Both ends load compatible versions of the plugin.
- tmux provides `pane_left`, `pane_top`, `pane_width`, `pane_height`,
  `window_width`, `window_height`, `pane_at_*`, `socket_path`, and `session_id`
  formats. The implementation is tested with tmux 3.4 and 3.6.
- The inner tmux emits its configured terminal title, SSH transports it
  unchanged, and the outer tmux records it as `pane_title`.
- No program between the inner and outer tmux permanently replaces the peer
  title while navigation is expected to work.
- The plugin owns the server's `set-titles` and `set-titles-string` options.
  Other title-management configuration is incompatible with peer discovery.
- The session's active window and pane are shared tmux session state. Multiple
  clients attached to the same session therefore intentionally navigate that
  same session state.

## Geometry assumptions

Pane coordinates are normalized between the inner and outer rectangles.
Selection first minimizes distance in the requested direction, then minimizes
distance from the mapped perpendicular coordinate.

This assumes:

- tmux's reported window geometry represents the layout rendered for the
  relevant client.
- Normalized pane centers are a useful measure of visual alignment when inner
  and outer windows have different dimensions.
- Borders and status lines may change dimensions by a cell but do not change
  the intended relative pane ordering.

If several clients attach to one session with different terminal sizes, tmux's
window-size policy determines the reported geometry. The plugin does not keep
a separate geometry model per attached client.

## Concurrency and ordering

Remote transitions use foreground `run-shell` commands. The invoking tmux
client therefore does not process later input until remote navigation has
finished, preventing typed input from reaching the previously focused pane.
Other clients attached to the server are not blocked.

All navigation bindings use foreground `run-shell` commands. Ordinary local
transitions still remain local and geometry-aware; remote transitions block
until the resulting selection is known.

The `navigate` and `enter` protocol operations combine state inspection and the
resulting remote selection into one request. The remote helper remains
authoritative for the current layout; failures fall back or are ignored rather
than selecting an unrelated pane.

## Trust model

The remote host is already trusted at the SSH account level. The descriptor can
name a readable Bash helper and tmux socket on that remote account. A malicious
remote process able to forge the pane title could influence which readable
remote script the local probe asks that same remote account to execute; it does
not grant access beyond the existing SSH identity.

Control sockets are placed in a directory created with mode 0700. OpenSSH's
hashed `%C` token prevents destination names from becoming filesystem paths.

## Fallback contract

Remote machinery is skipped when any prerequisite fails, including:

- no discoverable SSH destination
- no valid `TSR1` descriptor
- failed noninteractive SSH connection
- unreadable helper
- missing tmux socket or session
- malformed protocol output

When leaving an unavailable peer, tmux's ordinary directional `select-pane` is
used. When entering an unavailable peer, the outer SSH pane may still be
selected, but its inner state is not changed. No prefix or key sequence is sent
speculatively to an unverified remote.
