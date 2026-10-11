# Native sub-agent harness

Recipe for harnesses that have a first-class sub-agent mechanism (e.g.
Claude Code's Task tool, Codex sub-agents) when
[worker-delegation](../SKILL.md) detects such a harness. Passthrough mode:
the protocol contract still applies in full, but spawning uses the harness's
own native mechanism instead of an external daemon or app.

## Detection

Positive evidence, checked only after Orca and Paseo detection failed (the
precedence is Orca → Paseo → native):

1. The current harness exposes a built-in sub-agent spawning mechanism (for
   example a Task/sub-agent tool in the session toolset, or a documented
   native spawn API).

If evidence is ambiguous, stop and ask the user per the protocol's detection
rules.

## Capabilities

| Capability           | Supported | Notes                                                        |
| -------------------- | --------- | ------------------------------------------------------------ |
| `placement`          | no        | Workers run in the current checkout; do not pass placement contracts. |
| `question-channel`   | depends   | Only if the native mechanism supports mid-task interaction; otherwise the worker reports failure or a QUESTION in its final message. |
| `async-notification` | no        | Sub-agent results are returned synchronously to the supervisor. |
| `model-pinning`      | no        | Not supported by this harness.                               |

## Mechanics

- **Dispatch** (`ROLE`, `SLUG`, `TITLE`, `SPEC`): spawn a native sub-agent
  with the full task-spec text (protocol §4) as its prompt. Use `SLUG` as
  the sub-agent's description/label when the mechanism accepts one. The
  sub-agent runs to completion and its final message is the one-shot report.
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
