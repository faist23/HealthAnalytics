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

## Project
iOS SwiftUI app. Target: weekend warriors who want coaching guidance, not raw data dashboards.
