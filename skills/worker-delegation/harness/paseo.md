# Paseo harness

Recipe for the [Paseo](https://paseo.app) harness when
[worker-delegation](../SKILL.md) detects Paseo as the current harness.

## Detection

Positive evidence, checked in order — the first match wins:

1. `PASEO_AGENT_ID` is set (this session is itself a Paseo agent).
2. The session exposes the `mcp__paseo` MCP server through codemode —
   verify with `searchTools("paseo")`, `describeNamespace("mcp__paseo")`, or
   by filtering `ALL_TOOLS` for `mcp__paseo__*` names. In pi, MCP tools are
   never listed in the direct session toolset, so in pi a toolset check is
   never evidence; only the codemode discovery check counts. On a harness
   whose session toolset lists MCP tools directly, their presence satisfies
   this rule.
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
| `model-pinning`      | yes       | Model-default gate below.                                    |

## MCP access from pi (codemode)

When the coordinator runs under pi and the `mcp__paseo` MCP server is
configured, call the Paseo MCP tools from a `codemode` script:

- **Names:** `tools.mcp__paseo__<tool>({ ...args })`; hyphens become
  underscores (e.g. the MCP tool `get-agent-status` is
  `tools.mcp__paseo__get_agent_status`).
- **Discovery:** these tools are deferred — never listed in the session
  toolset or the codemode description. Find them with
  `searchTools("paseo")`, `describeNamespace("mcp__paseo")`, or
  `ALL_TOOLS`.
- **Results:** MCP tools resolve to a `CallToolResult` — prefer
  `structuredContent` (typed data, e.g. `providers`, agents, workspaces);
  fall back to `content[0].text`.
- **Sandbox limits:** the codemode sandbox has no Node APIs and no
  `process` — read environment variables (`PI_MODEL`, `PI_PROVIDER`,
  `PASEO_AGENT_ID`, `PI_SESSION_ID`) through the `bash` tool instead (e.g.
  `await tools.bash({ command: 'echo "$PI_MODEL"' })`).
- **Batching:** issue independent calls (provider listing, agent listing,
  parallel workspace creation) in one script with `Promise.allSettled()`.

## Authority: this file vs the installed `paseo` skill

- Resolve Paseo mechanics from the **installed `paseo` skill**
  (version-matched to the daemon). If it is not installed, fall back to
  `paseo --help`, `paseo <command> --help`, and https://paseo.sh/docs/cli.
  Never run `paseo ...` commands from memory.
- **Prefer the Paseo MCP tools**, called through codemode per
  "MCP access from pi" above, wherever an equivalent exists. When codemode
  or the `mcp__paseo` server is unavailable (non-pi harnesses, or the
  server is not configured), use the CLI fallbacks throughout. Also fall
  back to the CLI per call when no equivalent exists (notably logs
  harvesting, placement inspection, daemon status, provider diagnostics,
  and stop).
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

The repository default worker provider is **`pi`**. Use it unless the user
explicitly selects another supported provider; never silently switch
providers. It is an execution/runtime choice, not a product provider choice.

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
5. `command -v <agent>` and `<agent> --version` — executable present on PATH
   and able to report its version without prompting.
6. **Profiles:** if agent profiles are configured, consult them via the
   `list_profiles` MCP tool (CLI fallback: the installed `paseo` skill's
   profile discovery) and pick one the user requested or one whose notes
   match the work; otherwise launch with the validated default provider.
7. **Model-default gate** (capability `model-pinning`). Default dispatches
   (the common case) omit an explicit model, so every such worker resolves
   to the selected provider's configured default in the Paseo daemon config;
   explicitly user-selected models are validated per Dispatch mechanics
   instead and are not subject to this gate. For default dispatches, before
   the first dispatch, verify that default against the coordinator's own
   model:
   - Read `${PASEO_HOME:-$HOME/.paseo}/config.json` and resolve the selected
     provider's execution default: the entry with `"isDefault": true` under
     `agents.providers.<provider>.additionalModels` (for the default `pi`
     provider: `agents.providers.pi.additionalModels`). If no entry has
     `"isDefault": true`, the effective worker default is unverifiable —
     treat the gate as failed.
   - Compare that id with the coordinator's own model, which pi exposes as
     `PI_MODEL` (bare id) and `PI_PROVIDER` (provider prefix) on every
     spawned command, re-resolved at each command start. The gate passes when
     the config id equals `${PI_PROVIDER}/${PI_MODEL}` or the bare
     `PI_MODEL`; unset `PI_MODEL`/`PI_PROVIDER` (coordinator not running
     under pi) is a gate failure.
   - **On mismatch, stop before the first dispatch** and before any other
     side effect. Report the coordinator model and the config default
     verbatim, and tell the user to set `isDefault: true` on the intended
     entry in Paseo's provider settings (or `~/.paseo/config.json`) and run
     `paseo reload`, then re-invoke the skill. Never edit
     `~/.paseo/config.json` autonomously, never proceed on mismatch, never
     switch providers, and never fall back to inline work.

A preflight (pass or fail) is terminal for this invocation: the very next
action is the dispatch sequence of the invoking skill's chosen §3 pattern —
for the fire-and-forget handoff, the recipe below, whose workspace setup
(steps 1–2) precedes the launch — or, on failure, an explicit stop with a
precise failure report. Never re-enter the invoking skill's earlier phases
(Phase 0–2 where it defines them).

## Dispatch mechanics

- **Dispatch** (`ROLE`, `SLUG`, `TITLE`, `SPEC`, `PLACEMENT`): use the
  `create_agent` MCP tool — `provider` set to the combined
  `"<provider>/<model-id>"` form (e.g. `pi/openrouter/z-ai/glm-5.3-flash`;
  the first path segment is the provider, everything after it is the model
  id); the MCP surface rejects a bare provider with an input-validation
  error. The model id is either the daemon-resolved default validated by
  the model-default gate (step 7), or an explicitly user-selected model —
  validate the latter against the provider's model list (step 4's
  diagnostic or `list_models`) before dispatch; the gate continues to
  govern default dispatches only.
  `title` set to the kebab-case `SLUG`, `initialPrompt` set to the full
  task-spec text, `workspaceId` set to the supplied worktree workspace when
  the dispatch is anchored to one, and `notifyOnFinish` left enabled (the
  agent-scoped default) so the completion notification arrives without
  polling. Fall back to the `paseo run` CLI when codemode or the
  `mcp__paseo` server is unavailable; the CLI accepts a bare `--provider`
  as well as `provider/model`; the installed `paseo` skill owns its flags.
- **Parallel dispatch:** when §5 batching rules allow concurrent workers,
  create them in a single codemode script (`Promise.allSettled` over the
  `create_agent` calls) so they start together.
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
3. Launch the worker (`create_agent`; CLI: `paseo run`) with `provider` in
   the combined `provider/model` form (Dispatch mechanics above),
   `workspaceId` from step 2, a readable kebab-case `title`, and
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
