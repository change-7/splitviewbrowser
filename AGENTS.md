# AGENTS.md

## Project goal
- Build and maintain a native macOS split-view browser for AI web apps.
- Main use cases: view multiple AI services side by side, collect answers, send merged prompts to a target panel, manage presets and saved prompts.
- Current panel count: `1~5`, horizontal layout only.

## Tech stack
- Swift 5
- SwiftUI macOS App lifecycle
- AppKit bridging where needed
- `WKWebView` via `NSViewRepresentable`
- `UserDefaults` for persisted app state
- XcodeGen (`project.yml`) + Xcode project

## Run
- Regenerate project when source file structure changes: `xcodegen generate`
- Build: `xcodebuild -project SplitViewBrowser.xcodeproj -scheme SplitViewBrowser -configuration Debug -derivedDataPath build/DerivedData build`
- Run built app: `open -na ./SplitViewBrowser.app`

## Test
- Build tests: `xcodebuild -project SplitViewBrowser.xcodeproj -scheme SplitViewBrowser -configuration Debug -derivedDataPath build/DerivedData build-for-testing`
- Current automated runtime issue: `test-without-building` may hang in this environment.
- Focused tests live in `SplitViewBrowserTests/AppStateTests.swift`.

## Constraints
- Native macOS app only. Do not convert to Electron, browser extension, or web wrapper.
- Keep external links opening in the default browser, not inside the app.
- Horizontal panel layout only. Do not reintroduce removed grid mode unless explicitly requested.
- Custom sites do not automatically gain advanced collection/copy/send support.
- Preserve current user-facing features unless the user explicitly asks to remove them.

## Coding rules
- Prefer small focused files over large monolithic SwiftUI views.
- Prefer async/await and cancellable `Task` flows over chained `DispatchQueue.main.asyncAfter` when possible.
- Cache repeated DOM/script payload work to reduce needless `WKWebView.evaluateJavaScript` calls.
- Default to ASCII in source unless an existing file already uses Korean text for UI strings.
- After meaningful changes, update `VERSION_HISTORY.md` and refresh `GitHub_Public_Mac/`.
- Do not add destructive cleanup logic for user data, login sessions, or stored settings unless explicitly requested.
