# Native harness

Recipe for the current harness itself when [worker-delegation](../SKILL.md)
detects it — i.e. Orca and Paseo detection both failed. Native harnesses
(Claude Code, Codex, OpenCode, and similar agents) may or may not expose
their own sub-agent mechanism, and its shape is harness-specific. This file
therefore defines two modes, decided by a probe:

- **Sub-agent passthrough mode** — the harness exposes a usable sub-agent
  spawn mechanism; the protocol contract applies through it.
- **Synchronous mode** — no spawn mechanism is available; the supervisor
  executes delegated steps itself, sequentially, in this session.

## Detection

Native matches by elimination: after Orca and Paseo detection both failed
(including their ambiguity handling — stop and ask when evidence is
ambiguous), this harness file applies. No further evidence is required to
conclude native.

## Mode probe (once per session, before the first delegated step)

Probe the session for a sub-agent spawn mechanism:

1. **Toolset:** a tool that spawns an isolated sub-agent/sub-conversation
   and returns its result (names vary by harness: Task, subagent, spawn,
   run agent, …).
2. **Documented mechanism:** the harness's version-matched documentation
   describes a sub-agent feature (agent definitions, configuration, or CLI)
   usable from this session.

- Any hit → **sub-agent passthrough mode**. Resolve the exact usage from the
  mechanism's own documentation or tool description; never invent
  parameters, and never name an agent type or model from memory.
- No hit after both probes → **synchronous mode**. Announce it to the user
  once (e.g. "no sub-agent mechanism detected — executing steps in this
  session") and continue; do not stop.
- Unsure whether something qualifies as a spawn mechanism → stop and ask the
  user.
- If a spawn mechanism exists but fails on first use, stop and ask the user
  whether to continue in synchronous mode; never silently degrade mid-run.

## Capabilities

Mode-dependent. In synchronous mode the dispatch-based capabilities are not
applicable — the supervisor asks the user directly and validates its own
work.

| Capability           | Passthrough | Synchronous | Notes                                                        |
| -------------------- | ----------- | ----------- | ------------------------------------------------------------ |
| `placement`          | no          | n/a         | Workers run in the current checkout; do not pass placement contracts. |
| `question-channel`   | depends     | n/a         | Passthrough: only if the mechanism supports mid-task interaction; otherwise the worker reports failure or a QUESTION in its final message. |
| `async-notification` | no          | n/a         | Passthrough results return synchronously to the supervisor.  |

## Passthrough mechanics

- **Dispatch** (`ROLE`, `SLUG`, `TITLE`, `SPEC`): spawn a native sub-agent
  with the full task-spec text (protocol §4) as its prompt, using the spawn
  mechanism as its own documentation prescribes. Use `SLUG` as the
  sub-agent's description/label when the mechanism accepts one. The
  sub-agent runs to completion and its final message is the one-shot report.
  Spawn with the mechanism's default sub-agent type/model; never pin a
  specific agent type or model unless the user explicitly selects one. This
  is an execution/runtime choice, not a product provider choice.
- **Harvest**: the sub-agent's result is returned directly to the supervisor
  — this is both the live-catch and the terminal-state path; there is no
  separate log mechanism. Cross-validate the report against the observed
  result (protocol §6 step 5) exactly as with any other harness.
- **Wait**: synchronous — no waiting discipline needed beyond the general
  no-unbounded-wait rule.
- **Questions**: without a `question-channel`, a worker that needs a decision
  ends its report with an explicit QUESTION section and reports the step as
  blocked; the supervisor resolves it (possibly asking the user) and
  schedules a fresh dispatch with the answer included in the task spec.
- **Recovery**: recovery is a fresh native sub-agent dispatch with full
  context of what exists (protocol §7). A finished sub-agent is never
  resumed with follow-up work.

## Synchronous mode mechanics

The supervisor performs every delegated step itself, in this session, in the
invoking skill's step order — there is no dispatch, no wait/harvest, and no
worker report.

- Announce the mode once before the first delegated step; never stop because
  delegation is unavailable.
- Treat the invoking skill's role assignments (`implementer`, `explore`,
  `reviewer`) as checklists and gates rather than dispatches: exploration is
  read-only research, implementation follows the task spec's files-in-scope
  and acceptance criteria, and review is a read-only pass over the diff.
- A failed step is diagnosed and redone by the supervisor; when the invoking
  skill declares healing bounds, each redo counts as one attempt.
- Completion artifacts apply unchanged to the supervisor's own work:
  commits, pushes, PRs, verification records, and the PR description
  contract (protocol §9). §8 completion-proof blocks are worker-report
  artifacts and do not apply; the invoking skill's own gates validate the
  work.
- Never fake a worker with background shell jobs, detached processes, or
  daemon-style pseudo-workers — sequential execution in this session is the
  mode, not a substitute to be escaped from.

## Fire-and-forget handoff — not supported

Not supported in either mode: passthrough sub-agents are synchronous (the
spawn call blocks until the result returns), and synchronous mode has no
separate worker at all — so the supervisor can neither hand off ownership
nor stop supervising. If an invoking skill names this pattern (e.g.
`plan-feature` Option D), report that this harness cannot perform the
handoff and stop; suggest the invoking skill's non-handoff option (e.g.
Option C) as an explicit user choice. Never improvise the handoff with
background shell jobs or inline work.

## Invariants

- In passthrough mode, delegation is still mandatory: a step assigned
  `implementer`, `explore`, or `reviewer` must go to a real sub-agent —
  never inline in the supervisor's own turn (protocol §2).
- In synchronous mode, inline execution is the sanctioned mode itself
  (protocol §2 exception); announce it and execute sequentially.
- No substitute delegation: do not replace the harness's sub-agent mechanism
  with bare shell work, background shell jobs, or chat-only pseudo-workers.
- The PR description contract (protocol §9) applies unchanged in both
  modes; the completion-proof contract (protocol §8) applies to passthrough
  autonomous child workers only.
- Batching and parallel-dispatch rules (protocol §5) apply unchanged in
  passthrough mode; sub-agents may be spawned concurrently when the steps
  are independent. Synchronous mode is sequential by definition.