# HealthAnalytics: Architectural & Engineering Mandates

This document serves as the "Source of Truth" for the HealthAnalytics project. All future development, refactoring, and AI-assisted coding must adhere to these established patterns to ensure consistency and value for the athlete.

## 1. The "Single Source of Truth" Mandate

### Centralized Analysis
*   **The Brain:** All readiness, coaching, and injury risk logic **MUST** reside within `ReadinessRepository`. 
*   **No Redundant Logic:** ViewModels (e.g., `DashboardViewModel`, `ReadinessViewModel`) must **NEVER** calculate their own readiness scores or status levels. They must subscribe to `@Published` properties in `ReadinessRepository`.
*   **Reconciliation:** The `ReadinessRepository` acts as the "Master Coach." It is responsible for resolving conflicts between competing signals (e.g., high HRV but high injury risk).

## 2. Data Integrity & Stability

### The Data Fingerprint
*   To prevent "Score Drift" (e.g., a score changing from 81 to 78 simply by switching tabs), the app uses a `DataFingerprint` (see `PredictionCache.DataFingerprint`).
*   **Caching Rule:** If the fingerprint (counts of workouts, sleep, HRV, RHR) has not changed and it is the same calendar day, the app should use the cached `UnifiedReadiness` object rather than recalculating.

### Calendar-Based Math
*   **Anchor Points:** Always use `Calendar.current.startOfDay(for: Date())` for analysis windows.
*   **Stability:** Use fixed calendar days (e.g., "the 7 full days ending yesterday") rather than sample counts (e.g., "the last 7 samples") to ensure baselines don't shift when a single background data point is ingested.

### Intra-Day Recovery Decay
*   **The Decay Model:** Readiness is dynamic. After a workout, the score must decay immediately and recover exponentially over time (modeled in `RecoveryDecayService`).
*   **Real-Time Score:** The `ReadinessRepository` provides a live readiness score that reflects current fatigue levels throughout the day.

## 3. Coaching & Logic Hierarchy

### The Reconciler Rule
When signals conflict, the following hierarchy applies:
1.  **Injury Risk (ACWR) > HRV Readiness:** If Injury Risk is High/Very High, it **must** temper or override "Ready for Quality" HRV recommendations.
2.  **Low HRV Override:** If HRV is significantly suppressed (>10% below baseline), the advice must default to "Rest/Easy" regardless of low training load.
3.  **Sweet Spot:** The "Golden Zone" for training load (ACWR) is **0.8 – 1.3**.

## 4. UI & Design Standards

### Interactive Health Signals
*   The `SupportingMetricsCard` (Health Signals) tiles must always be interactive.
*   **Tap-to-Explain:** Tapping a card must trigger a `MetricConditionDetailView` popover that explains:
    *   **Current Condition:** The "Why" behind the color (e.g., "HRV is 12% below baseline").
    *   **Coach's Guidance:** A clear, actionable next step for the athlete.

### Color Semantic Meaning
*   **Blue/Green:** Stable / Optimal Zone.
*   **Yellow:** Monitoring / Slightly Off-Baseline.
*   **Orange:** Warning / Significant Deviation / High Risk.

## 5. Domain Context (Sports Science)

### Longevity & Aging
*   **Aging Alpha:** We calculate biological age by comparing the user's 10-year HRV/RHR trends against standard human biological decay curves.
*   **HRV Decay Model:** Standard population decline is roughly 1.5ms/year. An "Aging Alpha" > 0 indicates physiological aging is slower than chronological aging.
*   **MET-minutes:** We prioritize MET-minutes for activity volume because they are the standard in longevity research and do not rely on wrist-based heart rate estimates (which have high error rates).
*   **Target:** 600–1500 MET-min/week is the "Excellent" range based on WHO guidelines.
*   **VO2 Max:** Treat wrist-based VO2 Max as a "Trend" only, never as a primary readiness driver.

## 6. Development Workflow

### Performance Profiling
*   Use `PerformanceProfiler` to wrap all major analysis blocks. This ensures we can identify bottlenecks in HealthKit fetching or ML processing.

---
*This document is a foundational mandate. If a proposed change contradicts these rules, the conflict must be resolved before implementation.*
