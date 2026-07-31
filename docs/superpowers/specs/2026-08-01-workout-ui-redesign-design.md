# FitBud — Workout UI Redesign

**Date:** 2026-08-01
**Status:** Approved
**Builds on:** `2026-07-31-fitbud-ai-coach-design.md` (Stage 1 complete, 26 commits, 56 tests)

---

## 1. Goal

Replace Stage 1's placeholder UI — a single scrolling `VStack` of text rows — with a
crown-paged, number-led interface in the idiom of Apple's own Workout app, whose primary job is
to make **heart-rate zone discipline** legible at a glance while running.

The athlete's plan requires 80% of running minutes in Z1–Z2. Every run in his recorded history
sits at 85–92% of max HR. The UI's single most important function is making that mistake
impossible to miss.

## 2. Research: what Apple actually does

Two reference screenshots (`reference/`) were analysed directly, plus Apple Support's
documentation of the Workout app's views. The native Workout app is stubbed out in the
simulator ("This feature is not available"), so it cannot be inspected at runtime — our own
screens must be built and screenshotted to be verified.

**Apple's Heart Rate Zones view:**

- Elapsed time in **system yellow**, not white, at ~40pt with hundredths.
- Zones are **five horizontal segments, not a ring.** Inactive segments are heavily darkened;
  only the active zone is at full saturation, and it **widens** to carry a `♥ ZONE 3` caption in
  black. A white caret beneath marks position within the zone.
- Three number-led rows (`148♥`, `23:53 TIME IN ZONE`, `137BPM AVERAGE HR`): very large
  numerals with tiny two-line uppercase labels stacked to their **right**.
- **No cards and no boxes.** Left-aligned type on pure black.

**Apple's Activity view:** three concentric rings, each over a dimmed track of its own hue,
with gradient fills (Move red→pink, Exercise green→chartreuse, Stand blue→cyan).

**The design decision worth respecting:** Apple did not use a ring for zones. A ring encodes
progress through a cycle; a zone is a rung you occupy. They used a ladder for the ladder-shaped
thing.

**Where this app legitimately differs:** Apple has no run/walk concept. This athlete runs 5:1
intervals, which *are* cyclical, so a ring is the honest representation — of the interval, not
of the zone. The redesign uses both idioms for the things each actually fits.

## 3. Structure

`TabView` with `.tabViewStyle(.verticalPage)`, driven by the Digital Crown. Default selection is
page 1, so Controls sit one turn "up" — the vertical analogue of Apple placing controls left of
metrics.

| Page | Name | Content |
|---|---|---|
| 0 | **Controls** | Pause/Resume, End. Large tap targets. |
| **1** | **Effort** (default) | The zone ring. §4. |
| 2 | **Zones** | Five-segment bar, time in zone, average HR. Apple's layout. |
| 3 | **Metrics** | Elapsed, distance, pace, energy. |
| 4 | **Splits** | Per-kilometre rows with relative pace bars. |

Each page gets a `.containerBackground` wash tinted to its meaning (the Effort page's tint
follows the current zone colour).

`ScrollView` must not be nested inside a page unless the content genuinely overflows, because a
scrolling child competes with the crown for paging. Only the Splits page may scroll.

## 4. The Effort ring

One dominant moving element and one secondary scale.

**Phase ring (dominant).** A thick arc that *drains* over the current run/walk interval — full
when the 5-minute run begins, empty as the walk break arrives. Filled with the current zone's
colour, so the thing that moves is also the thing that carries the warning.

**Zone scale (secondary).** A thin five-segment arc immediately outside the phase ring, with a
needle at live heart rate. Inactive segments at 22% opacity; the active segment at full
saturation. Same visual grammar as Apple's bar, bent to the circle.

Note one deliberate divergence: on the **ring**, the active segment brightens but its **width
does not change** — segment widths are fixed to bpm proportions, because a segment that grew
would move the needle's frame of reference and make the scale lie. On the **Zones page** (page
2) the active segment *does* widen to carry its caption, exactly as Apple's bar does, since that
bar carries no needle whose position must stay truthful.

**Centre.** Heart rate at ~44pt SF Rounded, zone name beneath it, phase countdown below that.

### Geometry (exact, so it is unambiguous)

SwiftUI convention: 0° is 3 o'clock, angles increase clockwise.

- Both arcs sweep **240°, from 150° to 30°**, leaving a 120° gap centred on the bottom of the
  screen (6 o'clock) for the countdown text. A tachometer, not a closed ring.
- The zone scale divides those 240° in proportion to each zone's **bpm width** over the full
  133–207 range (74 bpm), so segment widths reflect real physiology rather than being equal
  fifths.
- `angle(forHeartRate:)` clamps to `[133, 207]`, then
  `150° + ((bpm − 133) / 74) × 240°`. Below Z1 pins to the start, above Z5 pins to the end.
- The phase ring is trimmed to the **fraction of the phase remaining**, so it empties clockwise.

Drawn with `Canvas`. The geometry is pure arithmetic and is unit tested without rendering
anything — see §8.

### Why this earns its complexity

80% of the athlete's running must be Z1–Z2, so a correctly-run block renders this ring calm
green for nearly its whole duration. Warmth means drift; red means stop. No number needs
reading. Applied to his existing history, it would have been orange-to-red on every single run —
which is precisely the feedback that has been missing.

## 5. Visual system

**Zone palette** (Karvonen, HRmax 207 observed, RHR 60):

| Zone | Name | BPM | Colour | Hex | Role |
|---|---|---|---|---|---|
| Z1 | Recovery | 133–148 | teal | `#32ADE6` | walk breaks, warmups |
| **Z2** | **Easy** | **148–163** | **green** | **`#30D158`** | **the target for 80% of running** |
| Z3 | Steady | 163–177 | chartreuse | `#C6F432` | tempo days only |
| Z4 | Threshold | 177–192 | orange | `#FF9F0A` | intervals only |
| Z5 | VO2max | 192–207 | red | `#FF375F` | too hard |

Hex values are given so the palette is unambiguous. Z1/Z2/Z4/Z5 are the system colours
(`.blue`-family teal, `.green`, `.orange`, `.pink`-family red) and may be expressed as such;
Z3's chartreuse is sampled from Apple's own active-zone segment and has no system equivalent, so
it is defined by hex.

Inactive zone segments render the same hue at **22% opacity** on black. Elapsed time uses system
yellow (`#FFD60A`).

**Typography.** SF Rounded throughout. Numbers heavy and `.monospacedDigit()` so digits do not
jitter as they change. Labels uppercase, `.caption2`, secondary, stacked to the **right** of
their number in up to two lines — Apple's grammar. Elapsed time in system yellow.

**Layout.** Pure black background. Left-aligned. **No cards, no rounded-rectangle containers,
no dividers.** The zone scale is the only chrome on the screen.

**Always-on display.** The Series 10 dims rather than sleeps during a workout. The design must
stay readable dimmed, which argues for high-contrast type and against thin weights or
low-opacity secondary text on the Effort and Zones pages.

## 6. Data the UI needs

All additions are pure, testable logic. **`HealthKitWorkoutRecorder` is not touched** — it is
the file the final Stage 1 review found two Critical defects in, and it was hardened and
verified.

| Addition | Location | Notes |
|---|---|---|
| `HRZone` model + zone table | `Models/HRZone.swift` | Hardcoded for this athlete, as `WorkoutConfiguration`'s presets are. Stage 2 sources it from the plan JSON's `zones` block. |
| `zone(for bpm:) -> HRZone?` | `Models/HRZone.swift` | Pure. |
| `angle(forHeartRate:)` | `UI/EffortRingGeometry.swift` | Pure; unit tested. |
| `timeInZone: [HRZone.ID: TimeInterval]` | `WorkoutEngine` | Accumulates the elapsed delta per ingest against the current zone. Deltas with no HR sample are not attributed. |
| `averageHeartRate: Double?` | `WorkoutEngine` | Running mean over samples, for live display only. `CompletedWorkout` keeps HealthKit's authoritative time-weighted average. |
| `remainingFraction(at:)` | `RunWalkCycler` | 1.0 at phase start → 0.0 at phase end. Stays stateless. |

`WorkoutState` gains `currentZone`, `timeInZone`, `averageHeartRate` and `phaseRemainingFraction`.

## 7. Start and summary screens

**Start.** Carousel-style full-width rows (`.listStyle(.carousel)`) rather than a plain `List`:
each session as a full-bleed row with its glyph, title, and run/walk ratio. The history probe
moves to the bottom as a plainer row — it is a diagnostic, not a workout.

**Summary.** Leads with distance and duration at hero size, then:

- a **stacked horizontal zone-breakdown bar** — time in each zone across the whole run, in the
  zone palette;
- split rows with bars scaled to relative pace;
- average HR, energy;
- the save-failure message, if any, still prominent above the numbers.

The zone breakdown is the most valuable single element in the redesign after the ring: it
answers "did I actually keep it easy today?" without interpretation, and over weeks it is the
evidence that the 80/20 rule is being followed.

## 8. Testing

The renderers are not unit tested; the arithmetic behind them is, and that is where the bugs
would be.

- **`angle(forHeartRate:)`** — zone boundaries map to the expected angles; 133 pins to 150°;
  207 pins to 30°; values below and above clamp rather than wrapping around the gap.
- **`zone(for:)`** — each boundary lands in the intended zone, no gaps or overlaps between
  adjacent ranges, out-of-range values return nil.
- **`timeInZone`** — a synthetic metric stream crossing zones accumulates the right totals; a
  stream with no heart rate attributes nothing; totals never exceed elapsed.
- **`remainingFraction(at:)`** — 1.0 at phase start, ~0 at the boundary, correct across a
  cycle, and unaffected by a jump in elapsed (the cycler stays stateless).
- **Summary zone breakdown** — bar segment widths are proportional and sum to 1 when any time
  has been recorded, and the view degrades sanely when no HR was ever sampled.

Visual verification is by building and screenshotting on the Series 10 46mm simulator, which
supplies synthetic distance but no heart rate — so the ring must also be checked with an
injected fake HR series, not only against a live workout.

## 9. Out of scope

- **Activity rings (Move/Exercise/Stand).** The reference image is a craft benchmark, not a
  feature request: those values come from `HKActivitySummary`, which this app does not read, and
  they say nothing about a training run. A progress-against-plan ring would be meaningful, but
  plan data arrives in Stage 2.
- **Cadence, stride length, ground contact time, vertical oscillation, running power,
  elevation.** These need new quantity types in the live workout builder, additional HealthKit
  permissions, and re-verification of the recorder — a week before the athlete's first long run.
  Deferred deliberately, and they are what would make Apple's Metrics 2 and Power views
  possible later.
- **Media controls page.** No music integration in this app.
- **Customisable view order.** Apple lets you reorder workout views; a single-user app does not
  need it.

## 10. Open questions

1. **Zone-crossing haptics.** The ring makes zone drift visible, but a haptic when leaving Z2
   would make it noticeable without looking. Tempting, and it fits the existing
   `WorkoutHaptic` mapping — but the plan's cue rules are Stage 4's job, and a buzz every time
   HR wobbles across a boundary would be maddening. Left out for now; revisit with real
   hysteresis once there is data from real runs.
2. **Whether the Effort page should replace the Zones page.** They overlap. Both are specified
   because it is unclear which will prove more useful on the wrist; after two weeks of running,
   one may simply be deleted.
