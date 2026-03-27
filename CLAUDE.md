# HealthAnalytics — Claude Code Instructions

## Design System
Always read `DESIGN.md` before making any visual or UI decisions.
All colors, typography, spacing, and aesthetic direction are defined there. Do not deviate without explicit user approval.

In QA mode, flag any code that uses hardcoded hex values, system default colors (`Color.green`, `Color.orange`, `Color.blue`, `Color.red`, `Color.purple`, `Color.yellow`, `Color.pink`, `Color.cyan`, `Color.gray.opacity(...)`), or inline font sizes instead of the design tokens defined in `DESIGN.md`.

Note: `MainTabView.swift` uses a legacy `AppColors` struct and is intentionally excluded from the token sweep until the tab system is refactored.

The primary design direction is **Warm Signal**: warm dark surfaces (`#0F0D0B` background), terracotta accent (`#E8885A`), SF Pro Rounded for hero numerals, SF Pro Text for coaching voice, SF Pro Mono exclusively for raw data/chart annotations.

## Architecture
See `GEMINI.md` for the full engineering mandate. Key rules:
- All readiness logic lives in `ReadinessRepository` — never in ViewModels
- Use `DataFingerprint` caching to prevent score drift
- ACWR sweet spot: 0.8–1.3

## Known Compiler Patterns

### SourceKit "Cannot find X in scope" — always noise
SourceKit reports false "Cannot find type/member in scope" errors throughout this project because it analyzes files in isolation without the full module graph. These are **not real build errors**. Only trust errors that appear in an actual Xcode build (`xcodebuild`) or from the Swift compiler directly.

### "Compiler unable to type-check expression in reasonable time" — `body` too large
When a SwiftUI `body` triggers this error, decompose it into:
- `private var mainView: some View` — owns the top-level container + background
- `@ToolbarContentBuilder private var toolbarItems: some ToolbarContent` — owns toolbar items
- Keep `body` as a thin modifier chain only

Applied to: `ReadinessView.swift`, `RecoveryDashboardView.swift`

### `.foregroundStyle(.tokenName)` type inference failures
In batch-compile contexts Swift sometimes fails to resolve shorthand `.tokenName` for custom `Color` extensions. Always use explicit `Color.tokenName` form (e.g. `Color.accent`, `Color.statusOptimal`) — never the dot-shorthand.

### `ForEach` with named tuple arrays — `Binding<C>` overload always wins
iOS 26.2 SwiftUI's compiler picks `ForEach.init<C>(_ data: Binding<C>, ...)` over `RandomAccessCollection` when named tuples are involved, regardless of input type. Fix: define a local `struct … : Identifiable` inside the View and use `ForEach(array) { item in }`.

Applied to: `InsightsView.swift` → `DataCollectionCard.ActivitySummary`

## Project
iOS SwiftUI app. Target: weekend warriors who want coaching guidance, not raw data dashboards.
