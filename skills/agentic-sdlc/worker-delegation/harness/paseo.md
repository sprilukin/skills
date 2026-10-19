# Paseo harness

Recipe for the [Paseo](https://paseo.app) harness when
[worker-delegation](../SKILL.md) detects Paseo as the current harness.

## Detection

Positive evidence, checked in order — the first match wins:

1. `PASEO_AGENT_ID` is set (this session is itself a Paseo agent).
2. The session toolset exposes the Paseo MCP tools (`create_agent`,
   `send_agent_prompt`, `list_agents`, `create_workspace`, `list_workspaces`,
   `list_providers`, `list_models`, `inspect_provider`, `list_profiles`).
3. `paseo status` reports a running daemon — **corroborating only:** a
   running daemon proves the Paseo app runs on this machine, not that this
   session lives inside Paseo. Daemon status alone is **ambiguous** — stop
   and ask the user; do not conclude Paseo.

If evidence is ambiguous, stop and ask the user per the protocol's detection
rules.

## Capabilities

| Capability           | Supported | Notes                                                        |
| -------------------- | --------- | ------------------------------------------------------------ |
| `placement`          | yes       | Paseo worktree workspaces (`create_workspace`).              |
| `question-channel`   | yes       | `send_agent_prompt` (worker resumes in existing conversation).|
| `async-notification` | yes       | `notifyOnFinish` on `create_agent` / background `send_agent_prompt`. |

## Authority: this file vs the installed `paseo` skill

- Resolve Paseo mechanics from the **installed `paseo` skill**
  (version-matched to the daemon). If it is not installed, fall back to
  `paseo --help`, `paseo <command> --help`, and https://paseo.sh/docs/cli.
  Never run `paseo ...` commands from memory.
- **Prefer the Paseo MCP tools** over the CLI wherever an equivalent exists.
  Detect availability once per session: if your toolset does not list these
  tools, treat the MCP surface as unavailable and use the CLI fallbacks
  throughout. Also fall back to the CLI per call when no equivalent exists
  (notably logs harvesting, placement inspection, daemon status, provider
  diagnostics, and stop).
- The installed `paseo` skill's general guidance ("don't poll — the
  notification will tell you") targets single fire-and-forget agents. It does
  **not** fit a supervisor that must batch, parallel-dispatch, and reconcile
  multiple workers. For supervised delegation loops, the protocol's
  wait/harvest discipline **overrides** that guidance.
- Allowed CLI verbs for this protocol (verified against the installed CLI;
  re-check flags with `paseo <verb> --help` when versions may have changed):
  `status`, `ls`, `run`, `wait`, `inspect`, `logs`, `send`, `stop`,
  `workspace ls|create|archive|rename`, `provider ls|diagnostic|models`.
  Do not invent other verbs or flags.

## Preflight (once per session, before the first dispatch)

The worker provider defaults to the coordinator's own provider. Resolve it
by self-lookup: read `PASEO_AGENT_ID` from the environment and look this
agent up (`paseo inspect "$PASEO_AGENT_ID"`, or `paseo ls` / `list_agents`);
the returned provider is the default. Then validate it is enabled/available
via `paseo provider ls` / `list_providers`. If the user explicitly selects a
provider, use theirs instead. If self-lookup fails, yields no provider, or
the resolved provider is unavailable, stop and ask the user — never guess,
never name a provider from memory. This is an execution/runtime choice, not
a product provider choice.

1. `paseo status` — confirm the daemon is running. If not, start it per the
   installed `paseo` skill; stop if that fails.
2. Confirm you are running inside Paseo when the invoking skill requires it
   (its task spec says so): `PASEO_AGENT_ID` is set and `paseo ls` shows your
   own agent. Outside Paseo, stop and tell the user.
3. Provider availability — use the `list_providers` MCP tool (CLI fallback:
   `paseo provider ls`); require the selected provider present with status
   `available` and enabled.
4. `paseo provider diagnostic <provider>` — require the daemon-resolved
   binary, version, and model list to be healthy. Never print credentials,
   tokens, or secret configuration.
5. The provider's executable — `command -v <executable>` and
   `<executable> --version` for the daemon-resolved binary reported by step
   4 — present on PATH and able to report its version without prompting.
6. **Profiles:** if agent profiles are configured, consult them via the
   `list_profiles` MCP tool (CLI fallback: the installed `paseo` skill's
   profile discovery) and pick one the user requested or one whose notes
   match the work; otherwise launch with the validated coordinator-default
   provider (resolved per the preamble).

## Dispatch mechanics

- **Dispatch** (`ROLE`, `SLUG`, `TITLE`, `SPEC`, `PLACEMENT`): use the
  `create_agent` MCP tool — `provider` set to the validated provider,
  `title` set to the kebab-case `SLUG`, `initialPrompt` set to the full
  task-spec text, `workspaceId` set to the supplied worktree workspace when
  the dispatch is anchored to one, and `notifyOnFinish` left enabled (the
  agent-scoped default) so the completion notification arrives without
  polling. Fall back to the `paseo run` CLI when the MCP tool surface is
  unavailable; the installed `paseo` skill owns its flags.
- **Follow-up / question answer**: `send_agent_prompt { agentId, prompt }`
  (CLI fallback: `paseo send <id> "<answer>"`).
- **Inspect**: `paseo inspect <id>` — shows `Cwd`, `ParentAgentId`, state.
- **Logs / harvest**: `paseo logs <id>` — read the final assistant message.
- **Wait** (CLI-only fallback): `paseo wait <id> --timeout 900` (the
  `WORKER_WAIT_TIMEOUT` default, passed explicitly).
- **List**: `list_agents` (CLI fallback `paseo ls`; global + archived for
  resume scans: `paseo ls -g -a --json`).
- **Placement surface** (capability `placement`): `create_workspace` /
  `list_workspaces` (CLI fallback `paseo workspace ls|create`).

## Fire-and-forget handoff recipe

Used by `plan-feature` Option D (and any invoking skill that names this
pattern). Input: target repo, working branch name, worker prompt.

1. Run `git fetch origin` in the current checkout — the working-branch ref
   must exist locally before workspace creation or the checkout fails.
2. Create the workspace (`create_workspace`; CLI: `paseo workspace create`)
   with `isolation: "worktree"`, `mode: "checkout-branch"`,
   `branch: "<working branch>"`, and `worktreeSlug: "<N>-<slug>"`.
   `checkout-branch` mode checks the existing working branch out directly,
   so no in-workspace `git switch` is needed — verify the returned workspace
   descriptor (path plus branch) instead. Workspace creation runs Paseo's
   repo setup hooks so dependencies are installed for later test runs.
3. Launch the worker (`create_agent`; CLI: `paseo run`) with the validated
   provider, `workspaceId` from step 2, a readable kebab-case `title`, and
   `initialPrompt` set to the supplied prompt, delivered exactly once
   (re-sending the same prompt queues a duplicate steering message in the
   worker's queue). Set `notifyOnFinish: false` — this is a fire-and-forget
   ownership handoff; the current session stops supervising.
4. Verify acceptance with a single read of the worker's output via
   `paseo logs <worker-id>` (no completion notification arrives because
   `notifyOnFinish: false`): confirm the delegated skill loaded and work
   started. Do not re-send the prompt.
5. Report the worktree path, branch, and worker id to the user.
6. Then stop: a handoff is done when the new workspace id and worker id have
   been reported and the prompt delivery was accepted. Do not supervise,
   monitor, or wait for the worker, and never also run the delegated skill in
   the current session.
7. Never paste secret values into prompts — reference ticket/epic numbers
   only; the worker reads issue bodies from GitHub.

## Placement verification

After a `PLACEMENT`-anchored worker starts: `paseo inspect <worker-id>` must
show `Cwd` = `WORKTREE_PATH` (and `ParentAgentId` = the supervisor, or an
explicitly accepted host session; `list_workspaces` can map the supplied
`workspaceId` to the expected path), and the worker's report must confirm its
branch. A worker that landed in the supervisor's workspace, the main
checkout, or another worker's workspace is a placement failure per protocol
§4.

## Wait/harvest mapping

Protocol §6 maps to Paseo as:

- inspect-before-wait → `paseo inspect <id>` / `paseo ls`
- completion notification → `notifyOnFinish` notifications from
  `create_agent` / background `send_agent_prompt`
- CLI wait → `paseo wait <id> --timeout 900`
- harvest from terminal state → read the last assistant message from
  `paseo logs <id>`, state from `paseo inspect`
- terminal states → `idle`, `error`, archived
