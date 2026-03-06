# SESSION_HANDOFF.md

## Done
- Native macOS SwiftUI split-view AI browser is working with `1~5` panels.
- Supported built-in services: ChatGPT, Gemini, Grok, Perplexity.
- Presets, prompt repository, quick compose, answer collection, analysis target sending, auto-copy settings, custom sites, backup/restore are in place.
- Recent optimization pass completed: `AppState` lookup cleanup, `WebViewStore` async flow cleanup, log deduplication, large view/file split.
- Current app bundle and public GitHub copy were refreshed.

## In progress
- No feature work is partially implemented right now.
- The only open technical thread is automated test execution stability in this environment.

## Problems
- `xcodebuild ... test-without-building` still hangs even though build and `build-for-testing` succeed.
- DOM-based automation remains sensitive to upstream site UI changes.
- `scripts/sync_github_public_mac.sh` hung once during the last session; the public folder was refreshed manually afterward.

## Next steps
1. Diagnose why macOS test execution hangs and restore a reliable full test run.
2. Add lightweight runtime profiling or counters for CPU/memory-heavy paths in `WebViewStore`.
3. If needed, harden the GitHub sync script or replace it with a simpler deterministic copy flow.
4. Continue feature work only after confirming current collection/send flows still work on the target sites.

## Related files
- `SplitViewBrowser/AppState.swift`
- `SplitViewBrowser/WebViewStore.swift`
- `SplitViewBrowser/WebViewStore+Scripts.swift`
- `SplitViewBrowser/ContentView.swift`
- `SplitViewBrowser/SettingsView.swift`
- `README.md`
- `VERSION_HISTORY.md`
- `SplitViewBrowser.app`
