# AI assistance

dwm-titus ships the `dwm-titus` customization and `dwm-titus-debug` diagnosis
skills from [titstack](https://github.com/ChrisTitusTech/titstack), adapted to
the current desktop. Each skill includes its MIT license. The imported source
revision is `bd3a1dbe9c33d7066dfe0e3561445472edcbe107`.
The runtime integration is adapted from
[Somnius's ai-assist branch](https://github.com/Somnius/dwm-titus/tree/ai-assist)
at `2f7bf158b7b07bf918e8f32ad9771bb9f3202f80`.

## Setup

Open Settings > AI assistant or run:

```sh
dwm-agent setup codex
dwm-agent status
```

Supported choices are `codex`, `opencode`, `gemini`, `claude`, `cursor-agent`,
and `hermes`. You need your own agent account or provider configuration.
The desktop never supplies credentials. Sign-in uses the agent's own terminal
or browser flow. Reopen Settings or press Refresh after it finishes.

Missing agents can be installed with `dwm-install-ai-agent NAME`, or explicitly
requested through `install.sh --install-ai-agent NAME`. Installation downloads
third-party software through an existing mise installation and changes its
user configuration. Install mise separately first; dwm-titus does not add a
system package repository for it. `dwm-install-ai-agent --dry-run NAME` prints the
plan without installing. Agent versions resolve through mise when requested;
they are not pinned desktop dependencies.

Skills live in `${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus/config/agents/skills/`.
Desktop installation links them into `~/.agents/skills`, `~/.claude/skills`,
`~/.cursor/skills`, and `~/.hermes/skills`. Existing files, directories, and
symlinks are preserved. Run `dwm-agent link-skills` to retry missing links.
A separately installed `/usr/share/dwm-titus/agents/skills` tree takes priority.
If your agent uses another skills location, point it at the packaged `SKILL.md`
and its reference files. The prompts also include the diagnosis skill path.

## Crash and hang diagnosis

Crash notifications are on by default. The session watches readable
systemd-coredump journal records for your UID and offers **Diagnose with AI**
or **Ignore**. A selected agent starts only after you click Diagnose. Without
a configured agent, the action opens setup. No core dump or log is uploaded
by the watcher. An agent may send the evidence it reads to its provider;
review its permissions and redact secrets before sharing reports.

Hang detection is off by default. Enable it in Settings or run:

```sh
dwm-agent set hang-detection on
dwm-agent set crash-notifications off
dwm-agent-diagnose window
```

dwm pings windows advertising `_NET_WM_PING` every five seconds and reports a
reply overdue by ten seconds. Windows without that protocol cannot be checked.
Games, VMs and busy applications can produce false alarms. Add exact window
classes, one per line, to `~/.config/dwm-titus/hang-ignore` to suppress their
offers. Recovery, closing the window, or disabling detection withdraws the
notification. **Wait** dismisses the offer; **Force quit** closes the client's
X connection and can lose unsaved work. It does not send a kill signal to an
application-supplied PID. A stopped process may need separate manual cleanup.

Diagnosis starts with a read-only prompt and preserves the agent's configured
approval and sandbox policy. It does not enable automatic approvals, disable
sandboxing, or authorize fixes. Sandbox-hidden services must be reported as
unverified rather than failed. Window titles are excluded from prompts; process
identifiers are sanitized and passed as arguments, never evaluated as shell code.

The panel now exposes notification action buttons and default body-click actions.
Critical notifications with actions stay available until answered or dismissed,
including in history while the notification remains open. Saved history after a
shell restart has no executable actions.

## Disable or recover

```sh
dwm-agent set hang-detection off
dwm-agent set crash-notifications off
```

These switches do not require a desktop restart. New installations need a fresh
session to start the crash watcher; updates to dwm require a new session for the
ping detector. Remove only the skill symlinks you chose to install to stop an
agent discovering these skills; retain unrelated skill directories. Existing
custom skills are never replaced by desktop setup.

Agent CLI releases and authentication behavior can change independently of the
desktop. A missing or timed-out status probe is not proof that credentials are
invalid. Use the agent's own sign-in command to verify uncertain state. Validation
uses mocked agent commands; it does not authenticate or send diagnosis requests
to all six providers.
