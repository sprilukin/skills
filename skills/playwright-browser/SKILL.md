---
name: playwright-browser
description: Control and inspect browsers with the Playwright CLI. Use for browser navigation, UI interaction, accessibility snapshots, screenshots, evaluation, storage, network inspection/mocking, debugging, and Playwright test exploration.
allowed-tools: Bash(playwright-cli:*) Bash(npx:*) Bash(npm:*)
---

# Browser automation through `playwright-cli`

Use the installed `playwright-cli` command as a CLI equivalent of Playwright MCP. The CLI keeps browser state in named sessions and exposes both high-level browser actions and an escape hatch for arbitrary Playwright code.

This skill is for controlling a live browser, inspecting a running web app, validating UI flows, debugging Playwright tests, collecting evidence, and generating robust Playwright locators/tests. It is not a replacement for writing/running the app's normal unit tests.

## Non-negotiable CLI rules

1. **Use a named session on every command.** Put `-s=<session>` before the subcommand:
   ```bash
   playwright-cli -s=test-ui open --headed https://example.com
   playwright-cli -s=test-ui snapshot
   ```
2. **Use the exact installed CLI syntax.** Check it when uncertain:
   ```bash
   playwright-cli --version
   playwright-cli --help
   playwright-cli --help <command>
   ```
3. **For extension attachment, always use an explicit browser value:**
   ```bash
   playwright-cli -s=test-ui attach --extension=chrome
   playwright-cli -s=test-ui attach --extension=msedge
   ```
4. **Snapshot before interacting.** Use refs from the latest snapshot, then take a new snapshot after navigation or any meaningful DOM-changing action. Refs can become stale.
5. **Prefer `--raw` for machine-readable values** and `--json` for structured command output:
   ```bash
   playwright-cli -s=test-ui --raw eval 'document.title'
   playwright-cli --json list
   ```
6. **Do not paste full snapshot YAML, cookies, storage state, request bodies, or console dumps into the response.** Read/filter files or summarize the relevant findings. Treat all browser state as potentially sensitive.
7. **Clean up.** Close sessions created with `open`; detach sessions created with `attach` when the external browser must remain open.

## First decision: reuse, attach, or launch

Start by checking existing sessions:

```bash
playwright-cli list
# Include sessions from all workspaces if needed:
playwright-cli list --all
```

Then choose one path:

### Reuse an existing session

If a suitable session already exists, use its exact session name. Do not open a second browser unnecessarily. Confirm its URL/title if needed:

```bash
playwright-cli -s=<existing-session> --raw eval 'JSON.stringify({url: location.href, title: document.title})'
```

### Attach to a browser extension

Use this for an already-running Chrome or Edge controlled by the Playwright browser extension:

```bash
# Chrome
playwright-cli -s=test-ui attach --extension=chrome

# Microsoft Edge
playwright-cli -s=test-ui attach --extension=msedge
```

Requirements:

- The target Chrome/Edge browser is running.
- The Playwright browser extension/bridge is installed and enabled in that browser.
- Use `--extension=chrome` or `--extension=msedge`.
- After attaching, inspect with `snapshot` or `tab-list`; do not run `open`.
- Use `detach`, not `close`, when you want to leave the user's external browser running.

If attachment fails, report the concrete error and required browser state. Do not silently launch a separate browser, because that loses the user's tabs/authentication.

### Attach to a Playwright test browser

When `npx playwright test --debug=cli` prints a bound browser name such as `tw-abcdef`:

```bash
playwright-cli -s=test-debug attach tw-abcdef
```

The positional name is the bound Playwright browser target, not the session name. Keep the debug test process running while exploring.

### Attach over CDP

For a browser exposing Chrome DevTools Protocol:

```bash
# Playwright channel discovery/connection
playwright-cli -s=test-ui attach --cdp=chrome
playwright-cli -s=test-ui attach --cdp=msedge

# Explicit CDP endpoint
playwright-cli -s=test-ui attach --cdp=http://127.0.0.1:9222
```

Supported channel values include `chrome`, `chrome-beta`, `chrome-dev`, `chrome-canary`, `msedge`, `msedge-beta`, `msedge-dev`, and `msedge-canary`. The browser must have remote debugging enabled.

For a running Playwright server endpoint, use:

```bash
playwright-cli -s=test-ui attach --endpoint=http://127.0.0.1:PORT
```

`--cdp` is for CDP; `--endpoint` is for a Playwright browser-server endpoint.

### Launch a new browser

Use a fresh named session when no suitable browser exists or isolation is required:

```bash
playwright-cli -s=test-ui open --headed https://example.com
```

`open` is headless by default. Use `--headed` for visual/manual work. Supported browser values are `chrome`, `firefox`, `webkit`, and `msedge`:

```bash
playwright-cli -s=test-firefox open --browser=firefox --headed https://example.com
```

For persistent profile data:

```bash
playwright-cli -s=test-persistent open --persistent --headed https://example.com
playwright-cli -s=test-profile open --profile=/absolute/path/to/profile https://example.com
```

Do not use a persistent profile for secrets or unless persistence is required. Prefer the in-memory default.

## Standard workflow

Before acting, state internally:

- URL or existing browser/session to inspect
- What will be checked or changed
- Expected observable end state

Then:

```bash
# 1. List/reuse or create/attach a named session
playwright-cli list
playwright-cli -s=test-ui open --headed https://example.com

# 2. Snapshot to discover accessible elements and refs
playwright-cli -s=test-ui snapshot --filename=/tmp/pw-test-ui-before.yaml

# 3. Read the snapshot file and identify only the refs needed
# 4. Perform one or more actions
playwright-cli -s=test-ui fill e5 'hello'
playwright-cli -s=test-ui click e7

# 5. Snapshot again at the next decision point
playwright-cli -s=test-ui snapshot --filename=/tmp/pw-test-ui-after.yaml

# 6. Verify with eval or a focused snapshot
playwright-cli -s=test-ui --raw eval 'JSON.stringify({url: location.href, title: document.title})'

# 7. Close or detach
playwright-cli -s=test-ui close
# or, for an attached external browser:
playwright-cli -s=test-ui detach
```

The CLI prints page status and often an automatic snapshot after commands. Use an explicit `--filename` when a snapshot is needed for later reading, diffing, or reporting.

## Page discovery and targeting

### Snapshots

```bash
playwright-cli -s=test-ui snapshot
playwright-cli -s=test-ui snapshot --filename=/tmp/pw-test-ui-page.yaml
playwright-cli -s=test-ui snapshot --depth=4
playwright-cli -s=test-ui snapshot --boxes
playwright-cli -s=test-ui snapshot e12
playwright-cli -s=test-ui snapshot '#main'
```

Snapshots are accessibility-oriented and expose refs such as `e12`. Use the most recent ref only. `--depth` reduces output; `--boxes` adds viewport-relative bounding boxes.

### Target syntax

All action targets accept:

- A current snapshot ref: `e12`
- A unique CSS selector: `#submit`, `form button[type=submit]`
- A Playwright locator expression, for example:
  ```bash
  playwright-cli -s=test-ui click "getByRole('button', { name: 'Submit' })"
  playwright-cli -s=test-ui fill "getByLabel('Email')" 'user@example.com'
  playwright-cli -s=test-ui click "getByTestId('save-button')"
  ```

Prefer accessibility refs/locators (`getByRole`, `getByLabel`, `getByText`, `getByTestId`) over fragile CSS or positional selectors. If a target matches multiple elements, narrow it rather than forcing a click.

### Inspect attributes and state

```bash
playwright-cli -s=test-ui --raw eval 'el => el.id' e12
playwright-cli -s=test-ui --raw eval 'el => el.className' e12
playwright-cli -s=test-ui --raw eval "el => el.getAttribute('data-testid')" e12
playwright-cli -s=test-ui --raw eval "el => el.getAttribute('aria-label')" e12
playwright-cli -s=test-ui --raw eval 'el => el.textContent' e12
playwright-cli -s=test-ui --raw eval 'el => el.value' e12
playwright-cli -s=test-ui --raw eval 'el => ({disabled: el.disabled, checked: el.checked, hidden: el.hidden})' e12
playwright-cli -s=test-ui generate-locator e12
```

`generate-locator` converts a ref/selector into a Playwright locator expression useful in tests. Use `--raw` when you need only the expression.

## Interaction commands

All commands below use the same named-session prefix. Replace `e12` with a ref from the latest snapshot.

### Navigation and page lifecycle

```bash
playwright-cli -s=test-ui goto 'https://example.com/path?a=1&b=2'
playwright-cli -s=test-ui go-back
playwright-cli -s=test-ui go-forward
playwright-cli -s=test-ui reload
playwright-cli -s=test-ui close
playwright-cli -s=test-ui detach
playwright-cli -s=test-ui delete-data
```

Quote URLs containing `&`, `?`, `#`, or shell metacharacters. `delete-data` deletes the session's browser data; it is more destructive than `close`.

### Click, input, and selection

```bash
playwright-cli -s=test-ui click e12
playwright-cli -s=test-ui click e12 right
playwright-cli -s=test-ui click e12 --modifiers=Shift
playwright-cli -s=test-ui click e12 --modifiers=Control --modifiers=Shift
playwright-cli -s=test-ui dblclick e12
playwright-cli -s=test-ui type 'text to insert'
playwright-cli -s=test-ui type 'submit text' --submit
playwright-cli -s=test-ui fill e13 'user@example.com'
playwright-cli -s=test-ui fill e13 'submit this' --submit
playwright-cli -s=test-ui select e14 'option-value'
playwright-cli -s=test-ui check e15
playwright-cli -s=test-ui uncheck e15
playwright-cli -s=test-ui hover e16
playwright-cli -s=test-ui drag e17 e18
playwright-cli -s=test-ui upload /absolute/path/to/file.pdf
playwright-cli -s=test-ui drop e19 --path=/absolute/path/to/file.png
playwright-cli -s=test-ui drop e19 --data='text/plain=hello world'
```

`type` operates on the currently focused editable element. Prefer `fill` with an explicit target for forms. `upload` accepts one or multiple absolute paths. Use `drop --path` or `drop --data` for drag-and-drop targets.

### Keyboard and mouse

```bash
playwright-cli -s=test-ui press Enter
playwright-cli -s=test-ui press ArrowDown
playwright-cli -s=test-ui keydown Shift
playwright-cli -s=test-ui keyup Shift
playwright-cli -s=test-ui mousemove 400 300
playwright-cli -s=test-ui mousedown
playwright-cli -s=test-ui mousedown right
playwright-cli -s=test-ui mouseup
playwright-cli -s=test-ui mousewheel 0 600
```

Use `press` for normal keyboard actions. Use `keydown`/`keyup` only when a held modifier/key is required. Mouse coordinates are viewport-relative CSS pixels.

### Dialogs

Register the response before triggering a dialog:

```bash
playwright-cli -s=test-ui dialog-accept
playwright-cli -s=test-ui dialog-accept 'text entered into prompt'
playwright-cli -s=test-ui dialog-dismiss
```

## Evaluation and advanced Playwright code

### `eval`: page or element JavaScript

`eval` accepts a JavaScript expression/function and optionally a target ref/selector:

```bash
playwright-cli -s=test-ui --raw eval 'document.title'
playwright-cli -s=test-ui --raw eval 'location.href'
playwright-cli -s=test-ui --raw eval '() => document.body.innerText'
playwright-cli -s=test-ui --raw eval 'el => el.textContent' e12
playwright-cli -s=test-ui eval --filename=/tmp/read-page.js
```

Use `--filename` for large evaluations. Keep output bounded with `JSON.stringify`, selectors, `.slice()`, or filtered arrays. Do not use page JavaScript to bypass the user-visible flow unless the task explicitly calls for inspection/debugging.

### `run-code`: arbitrary Playwright API

Use `run-code` when no dedicated command exists. The code must be one function expression receiving `page`; `import`, `export`, and `require` are not supported:

```bash
playwright-cli -s=test-ui run-code "async page => {
  await page.getByRole('button', { name: 'Refresh' }).click();
  await page.locator('[data-status=ready]').waitFor({ timeout: 10000 });
  return { url: page.url(), title: await page.title() };
}"
```

For multiline or complex code, use a temporary `.js` file:

```bash
playwright-cli -s=test-ui run-code --filename=/tmp/pw-flow.js
```

Useful advanced capabilities include:

```bash
# Wait for a specific state (prefer targeted waits over arbitrary sleeps)
playwright-cli -s=test-ui run-code "async page => {
  await page.getByRole('status').waitFor({ state: 'visible', timeout: 10000 });
}"

# Wait for a URL or load state
playwright-cli -s=test-ui run-code "async page => {
  await page.waitForURL('**/dashboard');
}"

# Frames
playwright-cli -s=test-ui run-code "async page => {
  const frame = page.locator('iframe#payment').contentFrame();
  await frame.getByRole('button', { name: 'Pay' }).click();
}"

# Page metadata
playwright-cli -s=test-ui run-code "async page => ({
  url: page.url(),
  title: await page.title(),
  viewport: page.viewportSize(),
  frames: page.frames().map(frame => frame.url())
})"

# Permissions and emulation
playwright-cli -s=test-ui run-code "async page => {
  await page.context().grantPermissions(['geolocation', 'clipboard-read']);
  await page.context().setGeolocation({ latitude: 51.5074, longitude: -0.1278 });
  await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' });
}"

# Clipboard
playwright-cli -s=test-ui run-code "async page => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  return await page.evaluate(() => navigator.clipboard.readText());
}"

# IndexedDB inspection
playwright-cli -s=test-ui run-code "async page =>
  page.evaluate(() => indexedDB.databases())"
```

For downloads, wait for the event before clicking:

```bash
playwright-cli -s=test-ui run-code "async page => {
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Download' }).click();
  const download = await downloadPromise;
  await download.saveAs('/tmp/' + download.suggestedFilename());
  return download.suggestedFilename();
}"
```

Use targeted waits (`waitFor`, `waitForURL`, `waitForFunction`) rather than fixed sleeps. Do not use `networkidle` as a test synchronization strategy unless diagnosing a special case where it is explicitly appropriate.

## Screenshots, PDF, and visual review

Save evidence under `/tmp/pw-<task>-<step>.*`:

```bash
playwright-cli -s=test-ui screenshot --filename=/tmp/pw-test-ui-home.png
playwright-cli -s=test-ui screenshot --full-page --filename=/tmp/pw-test-ui-full.png
playwright-cli -s=test-ui screenshot e12 --filename=/tmp/pw-test-ui-control.png
playwright-cli -s=test-ui pdf --filename=/tmp/pw-test-ui-page.pdf
playwright-cli -s=test-ui resize 1440 900
playwright-cli -s=test-ui resize 375 812
```

Take screenshots for visual verification, responsive checks, user-requested evidence, and error states—not as a substitute for snapshots or DOM evaluation.

For interactive user feedback/design review:

```bash
playwright-cli -s=test-ui show --annotate
```

This opens the Playwright dashboard in annotation mode so the user can mark the live page. Use the resulting annotation/snapshot/notes to continue. `show` without `--annotate` opens the normal dashboard. `show --port=0` starts a blocking HTTP dashboard server on a random port; use `show --kill` to stop its daemon.

## Tabs

```bash
playwright-cli -s=test-ui tab-list
playwright-cli -s=test-ui tab-new
playwright-cli -s=test-ui tab-new 'https://example.com/other'
playwright-cli -s=test-ui tab-select 0
playwright-cli -s=test-ui tab-close 1
```

Always run `tab-list` before selecting/closing by index. A tab index is not a snapshot ref.

## Browser state and authentication

The following commands operate on the current session/context:

```bash
playwright-cli -s=test-ui state-save /tmp/pw-test-ui.auth-state.json
playwright-cli -s=test-ui state-load /tmp/pw-test-ui.auth-state.json

playwright-cli -s=test-ui cookie-list
playwright-cli -s=test-ui cookie-list --domain=example.com --path=/
playwright-cli -s=test-ui cookie-get session_id
playwright-cli -s=test-ui cookie-set session_id '<placeholder>' --domain=example.com --path=/ --httpOnly --secure --sameSite=Lax
playwright-cli -s=test-ui cookie-delete session_id
playwright-cli -s=test-ui cookie-clear

playwright-cli -s=test-ui localstorage-list
playwright-cli -s=test-ui localstorage-get theme
playwright-cli -s=test-ui localstorage-set theme dark
playwright-cli -s=test-ui localstorage-delete theme
playwright-cli -s=test-ui localstorage-clear

playwright-cli -s=test-ui sessionstorage-list
playwright-cli -s=test-ui sessionstorage-get step
playwright-cli -s=test-ui sessionstorage-set step 3
playwright-cli -s=test-ui sessionstorage-delete step
playwright-cli -s=test-ui sessionstorage-clear
```

Security:

- Never print, report, commit, or paste real credentials, auth tokens, cookies, or storage-state contents.
- Use placeholders in examples and keep auth state in a temporary/gitignored path.
- Delete auth-state files after use when possible.
- Do not use `cookie-clear`, storage clears, or `delete-data` on a user's attached browser without explicit permission.
- `state-load` is most reliable before navigating to the target app; reload/open the target afterward if needed.

## Network inspection and mocking

### Inspect requests and responses

```bash
playwright-cli -s=test-ui requests
playwright-cli -s=test-ui requests --static
playwright-cli -s=test-ui requests --filter='/api/.*user'
playwright-cli -s=test-ui requests --clear
playwright-cli -s=test-ui request 5
playwright-cli -s=test-ui request-headers 5
playwright-cli -s=test-ui request-body 5
playwright-cli -s=test-ui response-headers 5
playwright-cli -s=test-ui response-body 5
```

Request indices are 1-based and refer to the most recent `requests` listing. `response-body` inlines text and saves binary data to a file. Use `--filename=/tmp/...` for large output.

### Route/mocking commands

```bash
playwright-cli -s=test-ui route '**/api/users' --status=200 --body='[{"id":1,"name":"Alice"}]' --content-type=application/json
playwright-cli -s=test-ui route '**/api/data' --body='{"ok":true}' --header='X-Test: mocked'
playwright-cli -s=test-ui route '**/*' --remove-header=cookie,authorization
playwright-cli -s=test-ui route-list
playwright-cli -s=test-ui unroute '**/api/users'
playwright-cli -s=test-ui unroute
playwright-cli -s=test-ui network-state-set offline
playwright-cli -s=test-ui network-state-set online
```

Quote patterns and JSON. Routes persist in the session until removed or the session closes. For conditional responses, response modification, delays, or aborts, use `run-code`:

```bash
playwright-cli -s=test-ui run-code "async page => {
  await page.route('**/api/login', route => {
    const body = route.request().postDataJSON();
    return body?.username === 'admin'
      ? route.fulfill({ body: JSON.stringify({ token: 'mock-token' }) })
      : route.fulfill({ status: 401, body: JSON.stringify({ error: 'Invalid' }) });
  });
}"
```

Do not mock production systems or modify request headers to remove authentication unless the task explicitly requires it.

## Console, tracing, video, and highlights

### Console diagnostics

```bash
playwright-cli -s=test-ui console
playwright-cli -s=test-ui console warning
playwright-cli -s=test-ui console error --clear
```

The minimum level includes messages more severe than it. Use `--clear` after collecting a known set of messages.

### Tracing

```bash
playwright-cli -s=test-ui tracing-start
# perform the smallest flow that reproduces the problem
playwright-cli -s=test-ui tracing-stop
```

Tracing captures action timing, DOM snapshots, screenshots, network activity, and console information. Record only the relevant flow because traces can be large. Locate the generated trace output from the CLI result and do not expose sensitive trace contents.

### Video

```bash
playwright-cli -s=test-ui video-start /tmp/pw-test-ui-flow.webm --size=1280x800
playwright-cli -s=test-ui video-chapter 'Login' --description='Entering credentials' --duration=1500
playwright-cli -s=test-ui video-show-actions --duration=600 --position=top-right --cursor=pointer
# perform flow
playwright-cli -s=test-ui video-hide-actions
playwright-cli -s=test-ui video-stop
```

Use video for demos or visual evidence. Prefer `run-code --filename` when a polished recording needs custom waits or the `page.screencast` overlay API.

### Highlight elements

```bash
playwright-cli -s=test-ui highlight e12
playwright-cli -s=test-ui highlight e12 --style='outline: 3px dashed red'
playwright-cli -s=test-ui highlight e12 --hide
playwright-cli -s=test-ui highlight --hide
```

Highlights are useful for visual confirmation and user review. Remove them when finished.

## Test generation and debugging

Every normal action prints equivalent Playwright code. Capture semantic locators for tests:

```bash
playwright-cli -s=test-ui --raw generate-locator e12
```

A good workflow is:

1. Explore with snapshots and CLI actions.
2. Record the generated role/label/test-id locators.
3. Add assertions manually with `expect` in the real test.
4. Prefer stable semantic locators and targeted waits.

To debug an existing Playwright test:

```bash
PLAYWRIGHT_HTML_OPEN=never npx playwright test path/to/test.spec.ts --debug=cli
# Wait for the printed Debugging Instructions and bound name, e.g. tw-abcdef.
playwright-cli -s=test-debug attach tw-abcdef
playwright-cli -s=test-debug resume
playwright-cli -s=test-debug snapshot
playwright-cli -s=test-debug console error
playwright-cli -s=test-debug requests --filter='/api/'
# use pause-at/resume/step-over if needed
playwright-cli -s=test-debug step-over
playwright-cli -s=test-debug pause-at path/to/test.spec.ts:42
```

Keep the test process alive while attached. Stop/clean it after exploration, then rerun the test normally. `pause-at`, `resume`, and `step-over` are primarily for a browser launched by Playwright's CLI debug mode.

For plan → generate → heal workflows, keep scenarios independent, use a seed/fixture for setup, and consult the installed Playwright CLI reference docs rather than inventing CLI options.

## Sessions and cleanup

```bash
playwright-cli list
playwright-cli list --all
playwright-cli -s=test-ui close
playwright-cli -s=test-attached detach
playwright-cli close-all
playwright-cli kill-all
```

Use `close-all` only when all local CLI sessions may be closed. Use `kill-all` only for stale/zombie CLI processes. It does not replace stopping a separately launched Playwright test process.

A default session can also be supplied by the environment:

```bash
PLAYWRIGHT_CLI_SESSION=test-ui playwright-cli open --headed https://example.com
```

Explicit `-s=<name>` remains preferred in agent commands because it makes state and parallel workflows obvious.

## Troubleshooting

### `no target specified for attach command`

The attach target was not parsed. Use an explicit target:

```bash
playwright-cli -s=test-ui attach --extension=chrome
playwright-cli -s=test-ui attach --cdp=chrome
playwright-cli -s=test-ui attach --cdp=http://127.0.0.1:9222
playwright-cli -s=test-ui attach --endpoint=http://127.0.0.1:PORT
playwright-cli -s=test-debug attach tw-abcdef
```

Always provide the browser explicitly: `--extension=chrome` or `--extension=msedge`.

### No browser/session

```bash
playwright-cli list
playwright-cli -s=test-ui open --headed https://example.com
```

If stale processes are suspected:

```bash
playwright-cli kill-all
```

### Extension attachment fails or hangs

Verify the browser is running, the extension is installed/enabled in that browser, and the browser value matches the target (`chrome` or `msedge`). Do not fall back to `open` when the task requires the user's existing tabs/authentication; report the failure instead.

### Ref not found or stale

Take a new snapshot and use a new ref. Refs are not stable across navigation and may change after React rerenders:

```bash
playwright-cli -s=test-ui snapshot --filename=/tmp/pw-test-ui-current.yaml
```

### Quoting failures

Quote URLs, selectors, glob patterns, JSON, JavaScript, and values containing spaces or shell metacharacters. For complex `run-code` or `eval`, use `--filename` and a temporary file.

### Browser missing

```bash
playwright-cli install-browser --list
playwright-cli install-browser chromium
```

Only install browsers when requested/necessary; do not modify the user's setup silently.

## Response style

After meaningful browser actions, summarize in 2–5 bullets rather than dumping CLI output. A final browser report should be concise:

```text
## Browser Task Result

Task: <what was checked or changed>
URL: <final URL>
Status: success | partial | failed

Findings:
- <observable result>
- <observable result>

Evidence: /tmp/pw-<task>-<step>.png (if captured)
Next steps: <only if needed>
```

Report attachment failures, authentication requirements, unexpected dialogs, network errors, and cleanup limitations explicitly.
