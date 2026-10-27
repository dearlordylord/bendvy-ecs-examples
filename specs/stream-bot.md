## Problem Statement

The mechanics-test bots make decisions immediately and are designed for repeatable simulation. The operator wants to watch a bot in the normal browser game: readable decisions, normal graphics and sound, automatic new runs, and strategy code that can change while a run continues.

The requested presentation is the existing browser game, not the native window. Native headless bots must remain available for mechanics testing without JavaScript or Python controllers and without presentation delays.

## Solution

Add an opt-in browser stream session using the normal game renderer, menus, HUD and audio. A replaceable JavaScript strategy runs in a dedicated Web Worker and supplies intentions and upgrade preferences. Bend remains authoritative for gameplay, compiled to JavaScript through the existing browser build. The shared Bend bot policy provides navigation and fallback; the browser feature does not introduce another implementation of combat or progression.

Viewers see considered upgrades and stable goals. The operator can edit and reload strategy code without restarting the world. Invalid edits preserve the working strategy; active strategy failures visibly fall back to Bend. Death and victory lead to readable transitions and further runs.

This is a foreground browser bot session. Recording and broadcasting are outside this task. Hidden tabs and sleeping devices do not have an uptime guarantee.

## User Stories

1. As a viewer, I want the normal browser graphics and HUD, so that the stream looks like the game people can play.
2. As a viewer, I want normal music and sound effects while watching the bot play.
3. As a viewer, I want upgrade offers to remain visible before confirmation, so that I can read them.
4. As a viewer, I want the selected recommendation highlighted before it is applied, so that I can follow the decision.
5. As a viewer, I want a concise current intention, so that the bot's movement is understandable.
6. As a viewer, I want persistent travel goals, so that movement does not become random frame-by-frame jitter.
7. As a viewer, I want emergency evasive movement to remain immediate, so that presentation does not make the bot deliberately helpless.
8. As a viewer, I want physical XP collection, so that the bot obeys the same collection rules as a player.
9. As a viewer, I want readable death and victory transitions followed by new runs, so that the session continues unattended.
10. As an operator, I want a simple browser entry into stream mode, so that no native executable is required.
11. As an operator, I want deliberate start, pause, resume and stop controls, so that I can manage the bot session.
12. As an operator, I want a compact viewing layout with accessible diagnostics, so that errors remain available without overwhelming the picture.
13. As an operator, I want to choose the initial setup and seed sequence, so that a session can be reproduced or varied deliberately.
14. As an operator, I want an isolated stream profile, so that unattended play does not overwrite my normal progression.
15. As an operator, I want to edit JS or TypeScript strategy code, so that priorities and personality are programmable.
16. As an operator, I want strategy-only reloads during a live run, so that edits do not require rebuilding Bend or resetting the game.
17. As an operator, I want explicit reload and optional local development reload notifications, so that hosted and development sessions both have a clear workflow.
18. As an operator, I want a broken replacement to leave the working strategy active, so that editing is safe during a stream.
19. As an operator, I want the active strategy revision displayed, so that I know which code is playing.
20. As an operator, I want bounded compatible memory migration on reload, so that the bot can retain useful intentions.
21. As an operator, I want incompatible memory resets reported, so that changes are understandable.
22. As an operator, I want a crashed or looping strategy to trigger visible fallback, so that it cannot freeze the interface.
23. As an operator, I want bounded recovery and diagnostics, so that repeated errors do not create unlimited work or logs.
24. As an operator, I want presentation timing configurable, so that the viewing pace can be adjusted without changing game mechanics.
25. As an operator, I want explicit hidden-tab and audio-suspension status, so that I understand why play or sound has paused.
26. As a strategy author, I want legal upgrade choices and relevant goal candidates supplied by Bend, so that I do not duplicate game rules.
27. As a strategy author, I want visible threats and remembered XP, so that decisions use player-like knowledge.
28. As a strategy author, I want risk, build and collection priorities adjustable in code, so that different styles are possible.
29. As a strategy author, I want a documented typed observation, intention and memory contract, so that strategies can be checked before activation.
30. As a strategy author, I want explicit execution and payload limits, so that I know the supported operating envelope.
31. As a maintainer, I want obsolete replies rejected, so that old runs or strategy generations cannot influence current play.
32. As a maintainer, I want presentation clocks separate from simulation ticks, so that paused upgrade phases still finish correctly.
33. As a maintainer, I want decisions and errors attributable to run and strategy revisions, so that bot behavior can be investigated.
34. As a mechanics-test user, I want native headless bots unchanged and free of browser presentation waits, so that testing remains fast and repeatable.
35. As a mechanics-test user, I want existing native visible and parallel-grid modes preserved, so that the new mode does not remove useful tools.
36. As a maintainer, I want actual browser-session evidence alongside the Bend laws, so that the feature is checked through its real interface.

## Implementation Decisions

- Implement in a separate worktree from canonical `master`. This specification covers the browser stream feature, not engine changes, deployment or the separate 100× performance campaign.
- Reuse the normal browser renderer, UI components and persistent audio engine. The entry may be a route or a compact control in the current UI; do not build a second game renderer or prescribe an unnecessary menu redesign. Preserve ordinary player mode.
- Keep physics, combat, RNG, spawning, XP, progression, legal choices and bot navigation/fallback in shared Bend code compiled for the browser. JS strategy supplies high-level goals, preferences and optional bounded player inputs. It cannot mutate authoritative state or introduce auto-credit XP. Do not copy the existing bot planner into TypeScript.
- Prefer a browser module strategy in a dedicated Web Worker over a Node sidecar or a strategy running on the rendering thread. Worker isolation permits termination of a looping strategy; it is not a security sandbox for hostile third-party code or a hard process-memory limit. Initially support trusted operator code only.
- Compare the Worker boundary against direct main-thread strategy execution during design review: direct execution is simpler but cannot contain an infinite loop without freezing the UI. Select Worker execution for the required fault recovery. Reuse existing browser runtime ownership instead of creating a second authoritative world in the strategy worker.
- Define one authoritative typed observation/intention contract derived through supported project tooling. In-process Bend passes typed values; the Worker receives bounded plain structured-clone data. Do not stringify the whole world, restore removed file-command controllers, hand-build JSON in Bend, or create a parallel manual schema generator. Coordinate with the typed-output work.
- Publish only relevant observations at decision cadence or events, not the full ECS every render or tick. Include legal offers, player/build status, bounded visible threats and discovered/remembered goals. Keep one pending advice request and coalesce superseded observations. Set and document concrete payload, memory, cadence and log bounds during the first slice.
- Reuse the Bend policy as the default/fallback, including physical collection, remembered XP goals and emergency steering. External advice must not block active combat or render progress. A pending reply uses a still-valid intention or Bend fallback.
- Requests identify session, run, request, generation, phase and decision/offer set. Bend admission logic rejects obsolete, expired, malformed, non-finite or unavailable actions. Browser monotonic time controls elapsed presentation time; simulation ticks describe gameplay causality. Clock readings and Worker events are external inputs, not proof assumptions that browser scheduling is reliable.
- Model presentation and advice admission in shared Bend session logic. During an existing upgrade pause, gather advice for a configurable initial 500 ms, freeze one legal recommendation or fallback at cutoff, then display it for a separate configurable minimum 1500 ms before committing once. Late replies cannot replace that recommendation or shorten dwell. Changed offer identity starts a new decision. Keep rendering active without sleeps or artificial gameplay ticks.
- Operator pause stops simulation, upgrade commits and next-run startup. Rendering and controls stay live. Dwell and transition delays count active presentation time and resume from their remainder. Invalidate outstanding advice on pause and request fresh advice on resume. Preserve an already frozen recommendation only while its decision identity remains valid. Candidate preparation may occur paused; activation waits for an eligible resumed boundary.
- Maintain stable travel goals and replan on danger, damage, invalid goals or being stuck. Configurable priorities may shape personality. Random movement jitter and delays on every input are not the realism model.
- Prepare replacements in fresh Workers; validate the exported contract and a bounded smoke decision before activation. Switch generations atomically at a decision boundary. If a recommendation is already frozen for dwell, defer activation until that recommendation commits or its decision is invalidated; a reload cannot strand the choice or shorten dwell. Candidate syntax, initialization or smoke failure retires that candidate and preserves a healthy active generation. Active-strategy failure triggers visible Bend fallback and bounded retry/backoff. Terminate retired Workers and invalidate their replies.
- Migrate only explicit bounded versioned plain-data policy memory. Preserve compatible data and report incompatible resets. Navigation memory stays with its Bend owner. New runs reset transient goals and request identity. Never migrate closures or arbitrary heaps.
- Serve strategies as browser-compatible JS modules under documented origin, CORS and CSP constraints. TypeScript requires strategy-only transpilation and checking before loading. Offer explicit reload; optional local development notifications can automate it after complete writes. Version the complete strategy dependency graph so dependency edits cannot silently reuse stale imports. No permanent accumulating import cache, mandatory embedded editor or unrestricted browser filesystem assumption.
- The hosted session runs on static browser assets without a persistent Node service. Local JS/TS development tooling is allowed for strategy builds only and must not become a native headless controller. Strategy edits do not rebuild Bend. Document the local edit/reload workflow and the hosted module update workflow separately.
- Start audio through an explicit user gesture and reuse the existing audio engine/context. Pause/resume/mute without duplicate contexts or effects across reloads and run rotation. Report suspended audio with an actionable resume control rather than promising autoplay-policy bypass.
- Define visibility separately from focus: a visible window may lose focus without pausing stream mode. On a hidden document, pause stream progression and accumulated presentation time explicitly; return visibly paused for operator resume. Do not accumulate unbounded catch-up ticks on return. Normal player-mode focus behaviour remains unchanged. Document foreground and power requirements; device sleep and hidden-tab execution are unsupported uptime conditions.
- Own automatic end-of-run display, seed progression and next-run startup in the session. Treat death/victory as expected. Expose genuine simulation failures and deliberately reset or stop rather than silently continuing corrupted state. Isolate stream progression from the normal player profile; persistence of stream-only progression is explicit configuration.
- Show compact intention, strategy revision, run identity, active/reloading/fallback/paused status and FPS/TPS. Keep errors and bounded decision/reload records accessible, including source identity and why fallback occurred. Do not invent strategy explanations. Stop closes owned Workers and scheduling/audio activity without affecting another tab.

## Testing Decisions

- The user approved one main acceptance seam: a real stream session. Use the actual browser application and public stream controls, strategy edits and strategy failures as inputs. Observe rendered frames, progression, audio, decision records and recovery. Do not substitute a native window or a mocked Worker-only harness.
- In the first vertical slice, start the browser session with a user gesture, receive actual legal offers from Bend in the strategy Worker, highlight its recommendation, keep frames progressing during dwell and commit exactly one legal choice afterward. Demonstrate a live strategy edit changing the next eligible decision without restarting the world.
- State and verify Bend laws for production session transitions: current-decision admission, stale run/generation rejection, legality, advice cutoff, exactly-once confirmation, minimum dwell, stopped simulation clock, pause/resume and recovery. Falsify and mutate late replies, duplicate commits and wrong-clock implementations. Laws constrain modeled production decisions; they do not prove browser rendering, scheduling, audio or arbitrary scripts.
- Use browser automation and targeted JS diagnostics where useful for the real Worker, module loading and UI boundaries. Prefer existing browser/session seams and Bend scheduler/driver fixtures. Assert external behaviour rather than function names or internal Worker counts. Include Chromium and WebKit coverage for the operator's Mac browser, documenting actual tested versions and any limitations.
- Exercise initial load errors, invalid candidates, dependency-only edits, rapid saves, incompatible memory, candidate smoke infinite loops, active decision loops/crashes, malformed replies and delayed replies after pause/reload/new run. A bad candidate leaves a healthy active strategy working; an active failure yields fallback while frames and controls remain responsive.
- Verify physical XP collection, persistent goals and emergency steering while advice is delayed. Inspect observation bounds and knowledge restrictions rather than assuming a bounded list cannot leak hidden information.
- Pause during advice, frozen recommendation dwell and between-run display. Verify no commit or new run while paused, remaining dwell on resume and rejection of pre-pause replies. Verify visibility hide/show, visible blur, audio suspension/resume and no unbounded catch-up. Exercise actual music/effects, mute and repeated run rotation without duplicated effects or profile corruption.
- Stop during pending advice, candidate preparation and between-run display. Verify that later replies cannot commit choices, restart runs or resume audio. Restart through public controls with a fresh session identity. Test reload during frozen recommendation dwell, including deferred activation and an invalidated offer.
- Verify ordinary browser player controls, focus handling, audio and normal-profile persistence after leaving stream mode.
- Preserve native headless and grid checks through existing entry points. If shared policy changes, compare deterministic actions/memory and gameplay observations at fixed seeds before and after. Verify native headless still runs without Node/Python and presentation waits. Summary parity alone is not proof of full-state equality.
- Use bounded functional browser checks for real decisions, reloads, recovery, lifecycle and audio. Preserve source/browser/strategy identities and failures. A 24-hour session is not an acceptance requirement and must not be started for this task. Do not claim that short functional checks establish continuous-operation reliability.
- No new headless speed campaign belongs here. Presentation timing deliberately differs from mechanics-test throughput.

## Out of Scope

- A native stream window, Node strategy service, Python controller, or replacing native headless/grid modes.
- Recording, video encoding, broadcasting, or configuring external streaming software.
- Changing balance, combat, XP or multiplayer rules for presentation.
- Multiplayer streaming, chat integration, Twitch/YouTube infrastructure or public deployment.
- Hidden-tab, minimized-window or sleeping-device uptime guarantees.
- Training, automatic retrospective learning, paid classifiers, or a validated human-behaviour model.
- Shipping other language adapters, a general mod sandbox or a mandatory embedded editor.
- Moving game mechanics out of Bend, engine/compiler changes, vendored ECS dependencies or Bend-to-WASM work.
- Restoring full-world serialization or solving unrelated build-system and performance issues.

## Further Notes

- The user explicitly selected a real stream session as the acceptance surface, then changed presentation from native to the normal browser game. This specification supersedes the earlier native/Node-sidecar proposal. No second approval of the same session seam is required.
- Applying `to-spec`: this is a specification in an isolated worktree, not a runtime implementation or deployment.
- The user clarified that recording is not requested and a 24-hour run must not be started now. This overrides the earlier inferred recording and long-run acceptance requirements. The required feature is an observable browser bot with replaceable strategy code.
- Earlier Astra review identified useful requirements retained here: separate advice cutoff from recommendation dwell, candidate from active-strategy failures, and operator from upgrade pause. Its native transport and long-run qualification recommendations do not define this task's acceptance. A second Astra review covered the browser revision; explicit frozen-dwell reload, stop/restart and ordinary-browser regression checks address its findings.
- Historical options research: https://github.com/dearlordylord/bendvy-ecs-examples/blob/master/research/stream-bot-policy-options.md
- Typed-output integration: https://github.com/dearlordylord/bendvy-ecs-examples/issues/18
- Export tooling: https://github.com/dearlordylord/bendvy-ecs-examples/issues/14
- Separate 100× goal: https://github.com/dearlordylord/bendvy-ecs-examples/issues/11
- Browser Worker lifecycle and messaging reference: https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers
- Browser visibility reference: https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API
