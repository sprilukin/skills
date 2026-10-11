# Native sub-agent harness

Recipe for harnesses that have a first-class sub-agent mechanism (e.g.
Claude Code's Agent tool, Codex sub-agents) when
[worker-delegation](../SKILL.md) detects such a harness. Passthrough mode:
the protocol contract still applies in full, but spawning uses the harness's
own native mechanism instead of an external daemon or app.

## Detection

Positive evidence, checked only after Orca and Paseo detection failed (the
precedence is Orca → Paseo → native):

1. The current harness exposes a built-in sub-agent spawning mechanism in
   this session's toolset — for example an `Agent`/`Task` tool, or a
   documented native spawn API.

Rejected evidence (never concludes native, and never resolves ambiguity):

- A CLI binary or app status (see the protocol's universal rejected-evidence
  rule) — `claude`/`codex`/`orca`/`paseo` on `PATH`, `claude doctor`,
  `orca status`, `paseo status`.
- Other harnesses' skills being installed or merely visible in this
  session's skill list — installed does not mean this session lives in that
  harness.
- Environment variables of other harnesses (`ORCA_*`, `PASEO_*`) — their
  presence is each harness's own predicate to evaluate, at higher precedence;
  absence here is not native evidence on its own.

If evidence is ambiguous, stop and ask the user per the protocol's detection
rules.

## Capabilities

| Capability           | Supported | Notes                                                          |
| -------------------- | --------- | -------------------------------------------------------------- |
| `placement`          | yes (prompt-directed) | The worker self-places: spawn-time worktree isolation when the mechanism offers it, branch checkout inside the worker per the task spec's placement contract. The supervisor never runs `git worktree`. |
| `question-channel`   | depends   | Only if the native mechanism supports mid-task interaction; otherwise the worker reports failure or a QUESTION in its final message. |
| `async-notification` | depends   | Yes for background-spawned workers (completion arrives as a notification); no for synchronous-only mechanisms (result returned in the same turn). |
| `model-pinning`      | no        | Not supported by this harness.                                 |

## Mechanics

- **Dispatch** (`ROLE`, `SLUG`, `TITLE`, `SPEC`): spawn a native sub-agent
  with the full task-spec text (protocol §4) as its prompt. Use `SLUG` as
  the sub-agent's description/label when the mechanism accepts one.
  - Prefer a **background spawn** when the mechanism supports one (completion
    is then delivered as a notification — `async-notification: yes`); a
    synchronous-only mechanism blocks the supervisor until the result
    returns, which is never acceptable for fire-and-forget (§ below).
- **Placement (prompt-directed)**: when a dispatch carries a placement
  contract, the worker creates or enters its own isolated workspace before
  touching files — with the mechanism's spawn-time worktree isolation when
  available (e.g. an `isolation: worktree` spawn option), otherwise its own
  checkout discipline — then performs the contract's checks: `git fetch
  origin`, `git switch <CHILD_BRANCH>` (DWIM-tracks `origin/<branch>`), and
  the §4 verification commands (`pwd`, `git branch --show-current`,
  `git rev-parse --show-toplevel`). A placement mismatch is reported as a
  placement failure, never edited through.
- **Harvest**: for background workers, the completion notification plus the
  returned final message is the one-shot report; for synchronous workers,
  the returned result is both the live-catch and the terminal-state path.
  There is no separate log mechanism. Cross-validate the report against the
  observed result (protocol §6 step 5) exactly as with any other harness.
- **Wait**: background workers fit the protocol §6 discipline (await the
  notification; `TIMEOUT` bounds the supervisor's own checkpoints).
  Synchronous workers return when they return — there is no separate wait.
- **Questions**: without a `question-channel`, a worker that needs a decision
  ends its report with an explicit QUESTION section and reports the step as
  blocked; the supervisor resolves it (possibly asking the user) and
  schedules a fresh dispatch with the answer included in the task spec.
- **Recovery**: recovery is a fresh native sub-agent dispatch with full
  context of what exists (protocol §7). A finished sub-agent is never
  resumed with follow-up work.

## Fire-and-forget handoff (pattern 1)

When the invoking skill requests a fire-and-forget handoff (e.g.
plan-feature Phase 5.5 option D), the supervisor:

1. Resolves the working branch and repo id per the invoking skill, then
   spawns exactly one background sub-agent. Give the spawn a readable label
   (`SLUG`), and prefer the mechanism's spawn-time worktree isolation so the
   worker does not run in the supervisor's checkout.
2. Builds the task spec from the protocol's template with a **placement
   contract** the worker executes itself:
   - `WORKTREE_PATH` / `CHILD_BRANCH` as supplied by the invoking skill;
   - first steps: `git fetch origin`, then `git switch <CHILD_BRANCH>`
     (DWIM-tracks `origin/<branch>`; never create a new branch — the
     working branch already exists on `origin`), then the placement checks
     (`pwd`, `git branch --show-current`, `git rev-parse --show-toplevel`);
     on any mismatch, stop and report a placement failure without editing
     files;
   - repo setup (dependency install, gitignored env-file **copying** —
     never reading their contents) before running the delegated skill;
   - then the `SKILL_COMMAND` exactly once.
3. Verifies acceptance from the worker's first output only (skill loaded,
   placement checks reported, turn started). Never re-send the prompt.
4. Reports the worker handle, workspace, and branch to the user, then
   stops supervising. A completion notification that arrives later is
   logged to the user and never re-opens supervision.

**Synchronous-only native mechanisms cannot honor pattern 1**: a spawn that
blocks the supervisor until completion is supervised delegation, not a
handoff. Stop and report the limitation to the user — do not run it as a
degraded fire-and-forget and do not silently supervise to completion.

## Invariants that do NOT relax in passthrough mode

- Delegation is still mandatory: a step assigned `implementer`, `explore`, or
  `reviewer` must go to a real sub-agent — never inline in the supervisor's
  own turn (protocol §2).
- No substitute delegation: do not replace the native sub-agent mechanism
  with bare shell work, background shell jobs, or chat-only pseudo-workers.
- The completion-proof and PR description contracts (protocol §8–§9) apply
  unchanged to autonomous child workers.
- Batching and parallel-dispatch rules (protocol §5) apply unchanged; native
  sub-agents may be spawned concurrently when the steps are independent.
- Prompt-directed placement does not relax placement verification: the
  worker reports the checks, the supervisor cross-validates them from the
  first output, and a mismatch is a placement failure (protocol §4).
