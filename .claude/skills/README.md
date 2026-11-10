# Claude Code skills for MockMyApp

Skills are folders with a `SKILL.md`; Claude Code lists each one by its `description` and loads
the body when a task matches. They travel with the repo, so every machine and every contributor
gets the same set (memory on one machine does not). All skill descriptions share one listing budget, so
this set is deliberately small: add a skill only when a milestone needs it, and remove it when
the milestone ends.

CLAUDE.md always wins over any skill. Third-party skills were reviewed and edited where they
conflicted with it; see `THIRD_PARTY.md` for sources, pinned commits, licences and every edit.

## Project skills (written for this repo)

| Skill | Use it for |
|---|---|
| `verify-offline` | Checking any change: format → analyze → targeted then full tests → offline PNG renders. Never launches the app |
| `studio-ui` | Any Flutter UI: tokens, `Studio*` components, the filled design language, the `StudioButton`-in-`StudioPanel` trap, phone vs desktop layout, offline screen renders, the on-device AI surfaces |
| `frame-calibration` | Device frames: generators, manifest, `measure_screen_rects.py`, `measure_body_rects.dart`, drawn frames, corner radius and rail width lessons, brand metadata |
| `template-authoring` | Store-listing templates: specs → displays → `generate_templates.py` → `dart format` → render; the copyright rule |

## Third-party skills (pinned, reviewed)

| Skill | From | Why it is here |
|---|---|---|
| `dart-run-static-analysis`, `dart-add-unit-test`, `flutter-add-widget-test`, `flutter-build-responsive-layout` | Flutter team (flutter/agent-plugins) | Analyzer loop, unit and widget tests, one codebase from phone to desktop |
| `riverpod` | evanca/flutter-ai-rules | The app's state management |
| `frontend-design` | Anthropic | Direction and copy for marketing surfaces; `studio-ui` overrides it for app chrome |
| `systematic-debugging`, `verification-before-completion` | obra/superpowers (files only, no plugin hook) | Root cause before fixes; evidence before claims |

Website skills live in `website/.claude/skills/` (its own repository) and show up as
`website:<name>`: `vercel-react-best-practices`, `web-design-guidelines` (vendored, no network
fetch), `wrangler`, `workers-best-practices`, `webapp-testing`.

## Guard rails in `.claude/settings.json`

It adds only an `ask` list, so these always prompt, even in auto mode:

- **App launches**: `flutter run|install|drive|attach`, `flutter -d`, any `flutter test` with `-d`,
  `--device-id` or an `integration_test` path, `adb install*|uninstall|shell` with or without a
  device selector, `xcrun simctl|devicectl`, emulators, `open` of a `.app` or `open -a`, and
  running `mockmyapp.exe`.
- **Live changes**: `wrangler deploy`, `versions deploy`, `versions upload`, `secret`, `rollback`
  and `delete` however they are invoked (bare, `npx`, `npx --no-install`), for the website.
- **Pushes**: `git push`, `git -C <dir> push`, `git -c <key>=<value> push`.

No allow rules, no plugins. Rules match the command text Claude writes, so a command run inside
`sh -c`, a script or a helper such as `webapp-testing`'s `with_server.py` is not matched. They are
a guard rail, not a security boundary; the CLAUDE.md prose still applies. The `wrangler` and
`mockmyapp.exe` rules match anywhere in a command, so a `grep` for that text prompts too.

## Not enabled, and how to enable one

The repo enables nothing from outside this folder (no plugins, no MCP servers) and recommends no
user-scope skills. Plugins can bring hooks and MCP servers, and a user-scope skill skips this repo's
review entirely.
So before any plugin or outside skill is enabled (candidates: `context7`; `claude-security`), pin
it to a commit, review it as `THIRD_PARTY.md` "Updating a pinned skill" describes, and record it
there. The research behind these choices is summarised in `THIRD_PARTY.md`, "Reviewed and not
installed".
