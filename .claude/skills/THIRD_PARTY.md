# Third-party skills: sources, pins, licences, local edits

Every third-party skill here (and in `website/.claude/skills/`) was copied from the commit below,
diffed against a fresh fetch of that commit, and read in full on 2026-10-02 before installation.
Each folder keeps its upstream licence file (`LICENSE` or `LICENSE.txt`). A skill with local
changes says so at the top of its `SKILL.md` in a "MockMyApp local edit" note; the changes are
listed here too. The project's own skills (`verify-offline`, `studio-ui`, `frame-calibration`,
`template-authoring`) are original to this repo.

Removed on 2026-11-10, when MockMyApp became free, open source and on the device only: the
cloud backend's and the store release's own skills, `flutter-use-http-package`,
`firebase-auth-basics`, `firebase-app-check`, and the six appeeky/aso-skills marketing skills with
their shared `.claude/app-marketing-context.md`. Nothing they covered is in the app any more.

## App repo: `.claude/skills/`

| Skill | Source (path @ commit) | Licence | Local changes |
|---|---|---|---|
| `dart-run-static-analysis` | [flutter/agent-plugins](https://github.com/flutter/agent-plugins) `skills/dart-run-static-analysis` @ `0ef3972f93e2baa4156ba1cbb1e515cd53079c68` | BSD-3-Clause, © 2026 The Flutter Authors | Project note (CI gate order, no analysis_options tightening, generated files) |
| `dart-add-unit-test` | same repo, `skills/dart-add-unit-test` | BSD-3-Clause | Project note; the line telling Claude to run `flutter test integration_test` now says integration tests launch the app and are the owner's |
| `flutter-add-widget-test` | same repo, `skills/flutter-add-widget-test` | BSD-3-Clause | Project note (phone surface, test font, asset loading) |
| `flutter-build-responsive-layout` | same repo, `skills/flutter-build-responsive-layout` | BSD-3-Clause | Project note (`StudioLayout` breakpoints); two workflow steps that said "resize the application window" / "test on desktop/tablet target" now say widget tests at sizes |
| `riverpod` | [evanca/flutter-ai-rules](https://github.com/evanca/flutter-ai-rules) `skills/riverpod` @ `7b9cce235714ae17acbae896b1e8c8627e128f4c` | MIT, © 2025 Ivanna; derived-source terms in the copied `ATTRIBUTION.md` | Project note (Riverpod 2.6, manual providers, no new deps) |
| `frontend-design` | [anthropics/skills](https://github.com/anthropics/skills) `skills/frontend-design` @ `8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4` | Apache-2.0 (`LICENSE.txt`) | Project note (`studio-ui` wins for app chrome; screenshots mean offline renders) |
| `systematic-debugging` | [obra/superpowers](https://github.com/obra/superpowers) `skills/systematic-debugging` @ `8ca22dba9a94f28898bbce59f2537ff4d87c747d` | MIT, © 2025 Jesse Vincent | Files only, no plugin or hooks; left out `CREATION-LOG.md`, `test-academic.md`, `test-pressure-1..3.md`; project note; references to `superpowers:test-driven-development` / `superpowers:verification-before-completion` point at installed skills; `find-polluter.sh` runs `$TEST_CMD` (default `flutter test`) instead of `npm test`; the Phase 1 multi-layer example prints only whether `IDENTITY` is set (it had `${IDENTITY:+SET}${IDENTITY:-UNSET}` and `env \| grep IDENTITY`, which print the value) and drops `security list-keychains` / `security find-identity -v`, leaving keychain listings to the owner |
| `verification-before-completion` | same repo, `skills/verification-before-completion` | MIT | Project note (evidence = `verify-offline`; never launch the app) |

## Website repo: `website/.claude/skills/`

Listed again in `website/.claude/skills/THIRD_PARTY.md`, because the website is its own repository.

| Skill | Source (path @ commit) | Licence | Local changes |
|---|---|---|---|
| `react-best-practices` (invoked as `vercel-react-best-practices`) | [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) `skills/react-best-practices` @ `063bee94c3f4df8453406c830b0a7df0f2860278` | MIT, as declared by the repo README and the SKILL.md `license:` field; the repo ships no licence file at this commit, so none is copied | Project note (static export, read Next 16 docs; CLIs only from the lockfile, so `svgo` only as a pinned devDependency through `npx --no-install`) |
| `web-design-guidelines` | SKILL.md adapted from vercel-labs/agent-skills `skills/web-design-guidelines` @ `063bee9…`; `guidelines.md` is `command.md` from [vercel-labs/web-interface-guidelines](https://github.com/vercel-labs/web-interface-guidelines) @ `e3d624baaf29dc1fc645aff3e38f03e564d2d6b1`, unchanged | MIT, © 2025 Vercel Labs (`LICENSE`) | Upstream fetches its rules from `raw.githubusercontent.com` on every run; this copy reads the pinned local `guidelines.md` instead, and overrides the "Title Case" rule (the site uses sentence case); `vendored-from` names the pinned commit, not `main`, and a refresh diffs two commits and reads the diff before bumping the SHA |
| `wrangler` | [cloudflare/skills](https://github.com/cloudflare/skills) `skills/wrangler` @ `41e0d19858946d18af9ee2c2feebbe2e11d829ff` | Apache-2.0 | Project note (deploys, secrets and rollbacks are the owner's; wrangler is not a dependency yet, so add it pinned with the owner's OK and run it through `npx --no-install`); removed the "Deploy an unauthenticated prototype" (claim deployment) row |
| `workers-best-practices` | same repo, `skills/workers-best-practices` | Apache-2.0 | None |
| `webapp-testing` | anthropics/skills `skills/webapp-testing` @ `8a1541c…` | Apache-2.0 (`LICENSE.txt`) | Project note (website only, never the Flutter app; output to the scratchpad; `with_server.py` runs `--server` through a shell, so `--server` is limited to `npm run dev` or `python3 -m http.server` for `out/`); the upstream "do not read the source" line is replaced |

## Reviewed and not installed

| Item | Why |
|---|---|
| Whole `dart-flutter` plugin (flutter/agent-plugins) | Its rule `flutter-hot-reload.md` tells Claude to hot reload after every edit, and its MCP server enables `launch_app`, `hot_restart`, `flutter_driver`: all against CLAUDE.md |
| `flutter-add-integration-test`, `flutter-fix-layout-issues`, `dart-fix-runtime-errors`, `flutter-add-widget-preview` | Drive a running app (launch, hot reload, widget-preview server) |
| `flutter-apply-architecture-best-practices` | Prescribes ChangeNotifier MVVM with provider/get_it; this app is Riverpod |
| `dart-collect-coverage`, `dart-use-pattern-matching`, `dart-resolve-package-conflicts`, `flutter-accessibility`, `store-listing-assets` | Safe, but outside the lean set (skill descriptions share one listing budget) |
| `firebase-basics` | Built around `npx -y firebase-tools@latest` (unpinned) project creation, init and deploy |
| appeeky `keyword-research`, `android-aso`, `app-preview-video`, `subscription-lifecycle`, `monetization-strategy`, `app-launch`, `localization` | Outside the lean set; the API-dependent ones (`asc-metrics`, `competitor-tracking`, `market-*`) need a paid account |
| cloudflare `web-perf`, `nextjs-on-cloudflare` | Outside the lean set; the latter pushes a vinext migration a static export does not need |
| obra/superpowers as a plugin | Its SessionStart hook injects "you MUST invoke a skill before ANY response", overriding CLAUDE.md |
| pbakaus/impeccable | Hooks run a launcher that downloads and executes a binary |
| Plugins and MCP servers (aws-core, context7, claude-security…) | Not enabled here by decision: `.claude/settings.json` adds only `ask` rules. Any one needs a pinned commit and a review under "Updating a pinned skill" before it is enabled (README) |
| rorkai/app-store-connect-cli-skills | Not installed at any scope: a user-scope skill skips this review, and its CLI can upload and submit builds, which are the owner's |

## Updating a pinned skill

1. Fetch the new commit into a scratch directory (`git init; git fetch --depth 1 <repo> <sha>;
   git checkout FETCH_HEAD`), and `git diff <old>..<new> -- skills/<name>` upstream.
2. Read every changed file in full, scripts included. Reject remote downloads or execution,
   instructions to override CLAUDE.md, launching or hot-reloading the app, deploying, pushing, or
   credential access.
3. Copy the folder over, re-apply the local changes listed above, update the SHA here.
