# Orca harness

Recipe for the [Orca](https://orca-app.dev) harness when
[worker-delegation](../SKILL.md) detects Orca as the current harness.

## Detection

Orca injects a distinctive `ORCA_*` environment-variable set into every
terminal pane it manages, so detection reads the session environment — the
same approach other agent harnesses use (Claude Code's `CLAUDECODE=1`,
Cursor's `CURSOR_TRACE_ID`, VS Code's `TERM_PROGRAM=vscode`).

Positive evidence, checked in order — the first match wins:

1. **Primary signal:** `ORCA_PANE_KEY` is set. This is Orca's pane identity
   (`<tabId>:<paneId>`); Orca's own managed hook scripts and status
   extensions gate on it, and it is injected into every agent terminal pane.
2. **Corroborating signals:** at least one of `ORCA_TAB_ID`,
   `ORCA_TERMINAL_HANDLE`, `ORCA_WORKTREE_ID`, `ORCA_WORKSPACE_ID`,
   `ORCA_AGENT_LAUNCH_TOKEN`, `ORCA_AGENT_HOOK_ENDPOINT`/`_PORT`/`_TOKEN`,
   `ORCA_APP_VERSION`, or `ORCA_USER_DATA_PATH` is set. Corroborating
   signals without the primary signal are **ambiguous** — stop and ask the
   user; do not conclude Orca.

Never count any of these as detection evidence:

- `ORCA_PI_STATUS_OWNED` — self-set by the orca-pi status extension at load
  in any terminal, including outside Orca.
- `orca` CLI presence (`command -v orca`) or a successful `orca status` —
  that only proves the Orca app is running on this machine, not that this
  session lives in an Orca pane. CLI presence and reachability are the
  session-setup runtime verification (step 1 below), not detection.
- Endpoint files under `~/Library/Application Support/orca/agent-hooks/` —
  app-level state with the same limitation.

Leak caveat: shells spawned from inside an Orca pane (a nested terminal, an
SSH session from an Orca shell) inherit the `ORCA_*` set. Child agents
legitimately inherit it from their parent Orca session, but an unrelated
terminal launched from an Orca pane would also match. When it matters,
cross-check: the path suffix of `ORCA_WORKTREE_ID`/`ORCA_WORKSPACE_ID`
(`<repoId>::<path>`) must match the enclosing Orca worktree of the current
working directory (`orca worktree list --json`, or the CLI's `active`
selector inferred from cwd). A mismatch is an ambiguity: stop and ask the
user.

If evidence is ambiguous, stop and ask the user per the protocol's detection
rules.

## Capabilities

| Capability           | Supported | Notes                                                        |
| -------------------- | --------- | ------------------------------------------------------------ |
| `placement`          | yes       | Orca-managed worktrees, each with its own UI group.           |
| `question-channel`   | yes       | Worker `ask`/`escalation`; supervisor `reply`.               |
| `async-notification` | no        | Completion is a one-shot lifecycle event; use inspect/harvest discipline (§6 of the protocol). |
| `model-pinning`      | no        | Not supported by this harness.                               |

## Authority: this file vs the live Orca skills

- Resolve Orca mechanics from the live global **`orca-cli` skill** (Orca
  executable resolution and the version-matched CLI guide) and the global
  **`orchestration` skill** (Run, Task, Dispatch, worker lifecycle, waiting,
  replies, and completion verification). Those guides own the exact commands
  and flags; **never run `orca ...` commands from memory, from this file, or
  from an invoking skill**, and never invent a substitute. If the live,
  version-matched Orca guide disagrees with anything here on mechanics, the
  live guide wins.
- "Delegate to the Orca skills" means: load the named skill, read it, and
  follow its recipe exactly. It does NOT mean "you may optionally consult
  it" or "use it as inspiration."

## Orca concepts mapped to the protocol

| Protocol concept | Orca realization                                                        |
| ---------------- | ----------------------------------------------------------------------- |
| Worker           | A TUI agent in an Orca terminal, started via `worker-start`.              |
| Dispatch loop    | Orca Task + Dispatch inside a session Run.                               |
| One-shot report  | `worker_done` (exactly once, then the Dispatch auto-transitions to terminal). |
| Question channel | Worker `ask`/`escalation`; supervisor `reply`.                           |
| Placement        | Orca-managed worktree, its own UI group, exact worktree selector.         |
| Harvest          | `dispatch-show` terminal state when the one-shot `worker_done` was missed.|
| Terminal states  | Dispatch `completed` / `failed` / `stopped` / `outcome_unknown`.          |

## Session setup (once per session, before the first dispatch)

The exact commands live in the Orca skills — load them and follow their
syntax (do NOT copy flags from here, and do NOT assume specific flag names
such as `--run`):

1. **Resolve Orca and confirm the app is running** (`orca-cli` skill:
   `status`, `open` if needed).
2. **Create or bind the session Run once** (`orchestration` skill:
   `run-create` with the work objective as the run objective). Reuse its Run
   id for every task in this session. Do NOT recreate the Run per step.
3. **Confirm orchestration is functional** (`orchestration` skill:
   `task-list`, scoped to the Run just created). A `run_required` response is
   a **setup-order issue** (the Run is not yet bound), not proof that
   orchestration is disabled — bind/reuse the Run and retry. Only if
   orchestration commands are entirely unavailable (a non-`run_required`
   failure) is orchestration disabled: tell the user to enable it in Orca
   Settings > Experimental and **stop**. Do not proceed inline.

Before creating orchestration state, inspect existing Runs and Tasks. Reuse
or bind exactly one safe Run across all resumed invocations. If multiple
matching Runs exist or ownership is ambiguous, stop for reconciliation; do
not create a second Run. Create one synthetic parent Task only when no
matching parent Task exists in the selected Run, and verify every
create/bind response is successful with a real ID before using it. Never
continue with a null, guessed, or unverified Run or Task ID.

## Worker provider and readiness preflight

The repository's default worker agent is **`pi`**; use it unless the user
explicitly selects another supported Orca TUI agent (`opencode`, `omp`,
`gemini`, `grok`, `aider`, …). The worker agent is an execution/runtime
choice, not a product provider choice. Do not copy a provider from an Orca
guide example without checking this host first.

There are two readiness regimes. Run only the checks for the selected
agent's regime; never run the other regime's checks:

- **Local TUI agents** (`pi`, `opencode`, `omp`, `gemini`, `grok`, `aider`, …
  — any agent Orca launches as a local executable): validate only with
  `command -v <agent>` and `<agent> --version`. Do NOT run
  `orca account list` or any managed-account diagnostic for these.
  `orca account` manages only Claude and Codex accounts, so missing
  Claude/Codex managed accounts must never block a `pi`/`opencode`/etc.
  session.
- **Managed-account agents** (`claude`, `codex` only): in addition to the
  executable check, run `orca account list --json` and require at least one
  signed-in managed account of that type before dispatch. Never print
  credentials, tokens, or secret configuration.

Stop before creating dispatches if the executable is absent, the selected
agent is `claude`/`codex` and no managed account is signed in, or
`worker-start --agent <agent>` fails. Tell the user exactly which agent is
unavailable and what must be installed, configured, or signed in. Do not
silently switch agents, dispatch a bare shell, or retry blindly.

Use the validated agent for every worker in this session unless the user
explicitly changes the agent and the replacement passes the same preflight.
Pass an explicit `TIMEOUT_MS=900000` to every worker start; do not rely on
Orca's shorter CLI default of 60000 ms.

## Dispatch mechanics (supervised loop)

For every dispatch, follow the `orchestration` skill's supervised worker
loop, passing the protocol's dispatch inputs (`ROLE`, `SLUG`, `TITLE`,
`SPEC`, `TIMEOUT_MS`, `WORKTREE`, `EXPECTED_FILES`, `MAY_MODIFY`):

1. Create the Task from the SPEC (the orchestration skill's
   `task-create` / `dispatch --inject` recipe). The `--inject` flag fills in
   the task/dispatch IDs and coordinator identity from the dispatch context —
   you do NOT substitute them manually in the spec.
2. Start the worker with `worker-start`, anchored to the exact
   coordinator-supplied worktree when a `PLACEMENT` is supplied: the
   `--worktree` input must be the exact existing child-worktree
   selector/path, not `current`, `active`, or an omitted value. Orca must
   create the delegated terminal in that worktree's own UI group. Verify the
   worker-start receipt and terminal listing before allowing the worker to
   proceed. A terminal in the main group or a different worktree is a
   placement failure: stop and report it; do not let the worker modify files.
3. Wait → handle result → verify via the orchestration skill
   (`check --wait` on `worker_done`/`escalation`/`question`, `reply` for
   escalations/questions, `dispatch-show` status `completed`), **subject to
   the wait/harvest discipline below**.
4. On `worker_done --outcome failed`: report the failure through the active
   Dispatch lifecycle and let the supervisor decide whether to create a
   fresh recovery Dispatch. Do not declare the step done, fix it inline, or
   silently retry it.
5. After completion, run `git diff --name-only` and compare to
   `EXPECTED_FILES`; flag any divergence to the user.

### Wait and result-harvest mapping

The protocol's §6 discipline maps to Orca as follows. A sub-worker's
`worker_done` is a one-shot: it sends it once, ends its turn, and idles, and
the Dispatch then auto-transitions to terminal. The `worker_done` message is
a transient lifecycle event; if you are not waiting at the exact moment it
fires, `check --wait` will miss it and then block forever on a Dispatch that
will never emit another lifecycle message. The defenses are mandatory:

1. **Inspect before every wait.** Before issuing `check --wait`, query the
   state with `task-list` (scoped to this session Run) or `dispatch-show`.
   Wait only when the target Dispatch is still `ready` or `dispatched`, or
   when a worker `ask`/`escalation` is explicitly pending a reply. A visible
   or idle terminal is not a waitable condition.
2. **Never unbounded-wait on a terminal Dispatch.** If the Dispatch is
   already `completed`, `failed`, `stopped`, or `outcome_unknown` when you
   inspect, do NOT call `check --wait` on it and do NOT send it follow-up
   mail expecting it to resume — it is terminal and will never emit another
   lifecycle message. Treat its terminal as an idle surface, not an active
   worker.
3. **Harvest the outcome from terminal state.** When a Dispatch is already
   terminal (the one-shot `worker_done` fired before you waited), read the
   `outcome`, `filesModified`, and any completion proof directly from the
   Dispatch's terminal state via `dispatch-show`. This harvest path is a
   first-class result-capture method, equivalent to catching `worker_done`
   live via `check --wait`.
4. **Cross-validate every result.** After every captured `worker_done` (live
   via `check --wait`) **or** every terminal-state observation (harvested via
   `dispatch-show`), independently validate the Task/Dispatch IDs, the worker
   `outcome`, and the Dispatch status against each other. Orca lifecycle
   completion alone is never semantic step completion: a `completed` Dispatch
   with a `failed` outcome, or with `outcome_unknown`, is not a success.

Terminal-state matrix (Orca states):

| Dispatch state                                          | Supervisor action                                                                                          |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ready` or `dispatched`                                 | `check --wait`; inspect liveness; answer a pending `ask`/`escalation`.                                     |
| `completed` with valid `worker_done` proof              | Harvest proof from state; reconcile files; continue. Do not retry.                                         |
| `completed` without required proof (or `outcome_unknown`)| Record protocol-invalid completion; create a fresh recovery `implementer` Dispatch in the preserved worktree/branch. |
| `failed` or `stopped`                                   | Use the live Orca guide's retry path only when it explicitly allows it (`--retry-of`); otherwise create a fresh recovery `implementer` Dispatch. |
| terminal (any of the above terminal states)             | Never re-wait, never mail it expecting resumption, never treat the idle terminal as an active worker.       |

5. **No active Dispatch ⇒ no unbounded wait.** If no Dispatch is
   `ready`/`dispatched` and no pending `ask`/`escalation` requires a reply,
   do not enter an unbounded wait. Reconcile Run/Task/Dispatch state, harvest
   any terminal outcome, schedule a valid recovery Dispatch, or stop with a
   precise failure report. Never sit in `check --wait` with nothing waitable.

### Parallel dispatch

Create all tasks on the session Run first, then start all independent
workers (`worker-start`), then wait on completions — do NOT wait between
dispatches. Apply the wait/harvest discipline to each parallel Dispatch: a
Dispatch may have auto-completed while you were starting its siblings, so
inspect each one's state before waiting and harvest any terminal outcome
instead of unbounded-waiting. See the `orchestration` skill's supervised loop
for the exact sequence. Do not use generic parallel subagents or direct
terminal prompts.

## Fire-and-forget handoff recipe

Used by `plan-feature` Option D (and any invoking skill that names this
pattern). Input: target repo, working branch name, worker prompt. Perform a
**full ownership handoff** via the `orca-cli` skill (create the worktree,
launch the agent, deliver the prompt, stop supervising):

1. First run `git fetch origin` in the current checkout — the working-branch
   ref must exist locally before worktree creation or the checkout fails.
2. Create a new Orca worktree for the repo, named `<N>-<slug>`, linked to the
   GitHub issue. Prefer root-level sidebar placement (no parent lineage)
   unless the user asked for it to be parented under the current worktree.
   Repo setup hooks should run so dependencies are installed for later test
   runs.
3. The worktree MUST end up checked out on the working branch. Orca's
   create-time base option cannot do this — it creates a NEW branch
   `feature/<worktree-name>` from the ref — so the branch must be checked
   out explicitly inside the new worktree after creation (`git switch
   <branch>` DWIM-tracks `origin/<branch>`).
4. Launch a default `pi` agent in that worktree and send the supplied prompt
   exactly once (re-sending the same command queues a duplicate steering
   message in the agent's queue).
5. Verify acceptance by reading the terminal (skill loaded, turn started),
   not by re-sending.
6. Set the workspace-card comment `<skill> started on <branch>` and report
   the worktree path, branch, and subagent terminal to the user.
7. Then stop: a handoff is done when the new worktree id and agent handle
   have been reported and the send receipt was accepted. Do not supervise,
   monitor, or wait for the subagent, and never also run the delegated skill
   in the current session.
8. Never paste secret values into prompts — reference ticket/epic numbers
   only; the subagent reads issue bodies from GitHub.

## Worktree/group isolation (mandatory)

Every placed worker must run in an independent Orca worktree context with
its own UI group; never place a worker in the coordinator's `main` worktree,
the active/current worktree, or a terminal merely opened in the main group.
Before dispatch, verify the exact worktree selector, absolute path, branch,
and Orca worktree/group identity, and pass that exact existing-worktree
selector to the supervised worker loop. Do not use `current`, `active`, an
omitted `--worktree`, or a bare terminal handle that resolves to the main
group. If Orca cannot prove that the worker terminal belongs to the supplied
worktree/group, stop rather than dispatching. Never delete worktrees; use
only live Orca worktree mechanics — never invoke `git worktree` directly.
