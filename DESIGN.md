# Design System — HealthAnalytics

## Product Context
- **What this is:** iOS SwiftUI performance health dashboard that tracks readiness, HRV, training load (ACWR), Strava workouts, nutrition, and sleep — then synthesizes it into a daily coaching recommendation.
- **Who it's for:** Weekend warriors and fitness enthusiasts who want a knowledgeable coaching voice, not raw data. They want to know "what should I do today?" not "here are 20 metrics."
- **Space/industry:** Sports science / performance health monitoring (iOS native app)
- **Project type:** iOS native SwiftUI app — dark-first, data-forward, used primarily in the morning and evening

## Aesthetic Direction
- **Direction:** Warm Signal
- **Decoration level:** Minimal — typography, color semantics, and the score ring carry all the visual weight. No gradients as decoration, no icon grids, no blobs.
- **Mood:** Biological warmth meets quiet precision. The morning open feels like picking up a journal, not reading a monitor. Not WHOOP's cold data-lab aggression, not Oura's passive luxury. A knowledgeable friend who already knows your body.
- **Positioning:** Every competitor chose cold-dark (WHOOP/Garmin) or warm-light (Oura/Apple Fitness). Warm-dark is the gap — approachable and credible simultaneously.

## Color System

### Foundation (Dark Mode — Primary)
| Token | Hex | Role |
|-------|-----|------|
| `background` | `#0F0D0B` | App background — near-black with brown warmth, not cold gray/black |
| `surface` | `#1C1915` | Cards, sheets, list rows |
| `surfaceRaised` | `#262118` | Elevated sheets, modal backgrounds, separators |
| `textPrimary` | `#F2EDE6` | Main text — warm white, slight cream (not stark `#FFFFFF`) |
| `textSecondary` | `#8C8078` | Supporting text, labels, captions |
| `textTertiary` | `#4D4540` | Deemphasized text, axis labels, timestamps |

### Brand Accent
| Token | Hex | Rationale |
|-------|-----|-----------|
| `accent` | `#E8885A` | Terracotta — communicates energy without aggression. Sunrise vibes. Neither WHOOP's punishment-red nor Garmin's corporate blue. Used on: score ring (high readiness), CTA buttons, active tab indicator, progress bars |
| `accentDim` | `rgba(232,136,90,0.12)` | Accent tinted background for coach recommendation cards |
| `accentBorder` | `rgba(232,136,90,0.22)` | Accent card border |

### Semantic Status Colors
These map directly to the existing Blue/Green/Yellow/Orange coaching logic in GEMINI.md. All hues are warm-shifted from system defaults.

| Token | Hex | Meaning | Maps from |
|-------|-----|---------|-----------|
| `statusOptimal` | `#4ADE8F` | Bio-green — HRV above baseline, ACWR in sweet spot | System `.green` |
| `statusRest` | `#5BA8FF` | Sky blue — recovery mode, scheduled rest | System `.blue` |
| `statusMonitoring` | `#F5C842` | Amber — off-baseline, caution (not alarm) | System `.yellow` |
| `statusWarning` | `#F07240` | Ember — high risk, significant deviation | System `.orange` |

### Dark Mode Strategy
Warm-dark is the primary mode. Dark surfaces with the warm undertone look better for chart rendering and morning/evening use. If light mode is added in a future phase:
- Background: `#FAF7F2` (warm off-white)
- Surface: `#FFFFFF`
- Surface Raised: `#F0EDE8`
- Text primary: `#1A1612`
- Keep all semantic and accent colors; reduce saturation by ~10%

## Typography
All typography uses the SF Pro system family — no external font loading required. This is both the practical (on-device) and aesthetic right choice: SF Pro Rounded reads as approachable and human; SF Pro Text reads as conversational coaching voice; SF Mono signals "this is a raw measurement."

### Role Assignments
| Role | SF Pro Variant | Size | Weight | Usage |
|------|---------------|------|--------|-------|
| Hero Numeral | SF Pro Rounded | 64pt | Bold | Readiness score. One per screen. This is the first thing the eye lands on. |
| Section Title | SF Pro Display | 28pt | Semibold | Tab/screen-level headings: "Today", "Readiness", "Training" |
| Card Title | SF Pro Text | 17pt | Semibold | Card headers: "Health Signals", "Training Load", "HRV Trend" |
| Coach Guidance | SF Pro Text | 15pt | Regular | The coaching voice (`MasterCoachSummary`). Sentence-level recommendations explicitly addressing morning-vs-current delta. Preceded by a 3pt `Color.accent` leading border with 8pt padding. |
| Metric Value (tile) | SF Pro Rounded | 22pt | Bold | Tile display values: "52ms", "7.4h", "1.04" |
| Label / Caption | SF Pro Text | 12pt | Medium | Tile subtitles, chart axis labels, baseline callouts |
| Data / Chart Axis | SF Pro Mono | 11pt | Regular | **Exclusively** for raw measurements, axis values, timestamps, ACWR decimals |

**The critical rule:** SF Pro Mono is reserved for raw measurements only. Everything else — especially coach guidance text — uses SF Pro Text. This distinction signals to the user: "when you see mono, that's a number from your body; everything else is a human talking to you."

### SwiftUI Usage
```swift
// Hero numeral
.font(.system(size: 64, weight: .bold, design: .rounded))

// Section title
.font(.system(size: 28, weight: .semibold, design: .default))

// Card title
.font(.system(size: 17, weight: .semibold, design: .default))

// Coach guidance
.font(.system(size: 15, weight: .regular, design: .default))

// Metric tile value
.font(.system(size: 22, weight: .bold, design: .rounded))

// Data / chart annotation
.font(.system(size: 11, weight: .regular, design: .monospaced))
```

## Spacing
- **Base unit:** 8pt (iOS standard grid)
- **Density:** Comfortable — not cramped like a data terminal, not spacious like a marketing site
- **Scale:**

| Name | Value | Usage |
|------|-------|-------|
| `xs` | 4pt | Tight internal gaps (icon + label, badge dot + text) |
| `sm` | 8pt | Default internal padding, stack spacing |
| `md` | 16pt | Card internal padding, section spacing |
| `lg` | 24pt | Between cards, section gaps |
| `xl` | 32pt | Major section separators |
| `2xl` | 48pt | Hero section vertical breathing room |

## Layout
- **Approach:** Grid-disciplined — consistent column alignment, predictable card stacks. The data density requires structure, not creative editorialization.
- **Card structure:** Scrolling vertical stack of cards within each tab. Cards have consistent internal padding (`md: 16pt`).
- **Max content width:** Full-width on iPhone (standard iOS layout margins apply automatically)
- **Border radius scale:**
  - `sm`: 8pt — small elements, badges, status pills
  - `md`: 16pt — cards, tiles, buttons
  - `lg`: 24pt — large sheets, bottom sheets, modal containers
  - `full`: 9999pt — pills, circular elements

## Motion
- **Approach:** Intentional — every animation should aid comprehension or provide satisfying feedback. No gratuitous motion.
- **Score ring:** Spring animation on load and score change: `.spring(response: 1.0, dampingFraction: 0.8)` — the ring "breathes in" when the score arrives. The 1-second duration is intentional; it gives the eye time to register the arc before reading the number.
- **Tab transitions:** Default SwiftUI tab behavior (no custom cross-fade needed)
- **Card popover (MetricConditionDetailView):** Standard sheet presentation

| Type | Duration | Easing | Notes |
|------|----------|--------|-------|
| Micro (icon state) | 80ms | ease-out | Status dot color changes |
| Short (badge appear) | 200ms | spring | Status badge fade-in |
| Medium (score ring) | 1000ms | spring(response:1.0, damping:0.8) | Score ring draw |
| Long (sheet present) | 400ms | ease-in-out | Modal sheets |

## Design Anti-Patterns (Never Do This)
- No purple/violet gradients as accent
- No 3-column icon grids with colored circles
- No centered-everything layouts
- No uniform bubbly border-radius on every element (use the radius scale)
- No gradient buttons as primary CTA
- No decorative blobs or background noise
- No raw `Color.green` / `Color.orange` — always use the semantic tokens above
- No hardcoded font sizes — use the named scale

## Implementation Notes

### SwiftUI Token Strategy
Define a `DesignTokens` namespace (or `AppColors`/`AppFonts` structs) as the single source of truth for all tokens. ViewModels should never hardcode hex values or font sizes.

```swift
// Recommended structure
extension Color {
    static let background = Color(red: 0.059, green: 0.051, blue: 0.043)  // #0F0D0B
    static let surface = Color(red: 0.110, green: 0.098, blue: 0.082)     // #1C1915
    static let surfaceRaised = Color(red: 0.149, green: 0.129, blue: 0.094) // #262118
    static let textPrimary = Color(red: 0.949, green: 0.929, blue: 0.902)  // #F2EDE6
    static let textSecondary = Color(red: 0.549, green: 0.502, blue: 0.471) // #8C8078
    static let accent = Color(red: 0.910, green: 0.533, blue: 0.353)       // #E8885A
    static let statusOptimal = Color(red: 0.290, green: 0.867, blue: 0.561) // #4ADE8F
    static let statusMonitoring = Color(red: 0.961, green: 0.784, blue: 0.255) // #F5C842
    static let statusWarning = Color(red: 0.941, green: 0.447, blue: 0.251)  // #F07240
    static let statusRest = Color(red: 0.357, green: 0.659, blue: 1.0)     // #5BA8FF
}
```

### Existing Code Alignment
- `HeroReadinessCard.swift` already uses `.system(size: 48, weight: .bold, design: .rounded)` for the score — migrate to 64pt per this spec, or keep 48pt if the ring constrains it
- `SupportingMetricsCard.swift` tiles: apply the `md: 16pt` radius and `surface` background token
- The `gradientForScore` in HeroReadinessCard should be replaced with the terracotta accent gradient for high readiness

## Design Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-23 | Initial design system created | Generated by /design-consultation. Two voices (Claude main + Claude subagent) independently converged on warm-dark surfaces and terracotta accent. |
| 2026-03-23 | Warm-dark background (#0F0D0B) chosen over cold dark | Differentiates from WHOOP/Garmin cold-dark; makes morning check-in feel like a journal not a monitor |
| 2026-03-23 | Terracotta accent (#E8885A) chosen | Communicates energy without aggression. Category defaults are blue (corporate) and red (alarm). Terracotta = sunrise energy. |
| 2026-03-23 | SF Pro Mono reserved for data only | Signals to user: mono = raw measurement, proportional = coaching voice |
| 2026-03-23 | Morning/Evening mode navigation | Risk C deferred to future phase — see TODOS.md for UX architecture proposal |
