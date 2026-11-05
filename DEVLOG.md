# Apex - Dev Log

A running journal of everything built, why it was built, and how it works.

---

## Session 1 - Foundation

### What
Built the entire Apex app from scratch.

### Why
Wanted a personal life-tracking app with gamification - something that actually uses all the health data on the Apple Watch and gives intelligent feedback, not just charts.

### Stack decisions
- **SwiftUI + SwiftData** - native iOS, no backend, fast, offline-first
- **HealthKit** - reads Apple Watch data (sleep, HRV, activity rings, workouts)
- **Gemini 2.5 Flash** (via Google AI API, stored under the key name `apex_claude_api_key` in UserDefaults) - free tier, used for meal analysis, daily plan generation, and coach chat
- **XcodeGen** (`project.yml`) - generates the `.xcodeproj` so the project config lives in version control rather than a binary

### Core architecture
```
Models/         - SwiftData @Model classes
Services/       - @Observable services (HealthKit, AI, Gamification)
Views/          - Feature views organised by tab
```

**5 tabs:** Today | Workouts | Nutrition | Progress | Coach

### Models built
| Model | Purpose |
|---|---|
| `UserProfile` | Name, XP, streaks, API key, GitHub username |
| `WorkoutSession` | Tennis + gym sessions, HealthKit UUID for dedup |
| `GymExercise` | Individual exercises linked to a session (cascade delete) |
| `TennisDetails` | Encoded as JSON string on WorkoutSession to avoid optional relationship complexity |
| `MealEntry` | Photo or text meal log with macro breakdown |
| `DailyPlan` | AI-generated day plan, stores raw JSON + user modifications |
| `Achievement` | 15 achievements seeded on first launch |
| `Project` | Focus projects (startup, study, fitness, etc.) |
| `MorningCheckIn` | Daily energy/sleep check-in, links to focus projects |

### Gamification
- XP points system with 10 levels
- Daily streaks (workout + meal)
- 15 achievements (seeded by `GamificationService.fetchOrCreateAchievements()`)
- `XPBadge` component shown everywhere XP is awarded

### Services
- **HealthKitService** - reads activity rings, sleep, HRV, resting HR, recent workouts, step count
- **ClaudeService** - Gemini API wrapper; meal photo analysis, daily plan JSON, chat
- **GamificationService** - processes workouts and meals into XP + achievement unlocks

---

## Session 2 - Personalisation + Focus + Calendar + Evening Check-in

### What
Extended HealthKit to pull deeper metrics, added GitHub integration, Calendar (EventKit), focus block timer, evening check-in flow, and wired everything into a central `ApexContext` passed to all AI calls.

### Why
The AI felt generic - it didn't actually know anything real about the user. Needed all available data piped into every AI request so responses reference actual numbers.

### New HealthKit metrics
Added to `HealthKitService`:
- `vo2Max` - programmatic unit only (`HKUnit.literUnit(with: .milli).unitDivided(by: ...)`) - the string form `"ml/kg/min"` crashes at runtime
- `weight`, `respiratoryRate`, `mindfulMinutes`
- 7-day trends: `weeklyAvgSleep`, `weeklyAvgHRV`, `weeklyAvgActiveCalories`, `weeklyWorkoutCount`

### ApexContext
Created `ApexContext` struct in `ClaudeService.swift` - a 30+ field data bundle assembled fresh on every AI call. Passed to `chat()`, `generateDailyPlan()`. Includes health, recovery, training history, focus projects, nutrition, calendar events, GitHub commits.

### New models
- **`FocusSession`** - logged when a focus timer stops (project name, category, duration, timestamps)
- **`EveningCheckIn`** - mood rating, accomplishments text, AI-generated summary + tomorrow priority

### New services
- **`CalendarService`** - EventKit, `requestFullAccessToEvents()` (iOS 17+), fetches today's events with time ranges
- **`GitHubService`** - hits GitHub public events API, counts today's commits by repo
- **`FocusTimerService`** - `@Observable` timer with start/stop, returns result tuple on stop

### New views
- **`FocusTimerCard`** - in Today tab; shows active projects as chips, tap to select, tap again to start. Running state shows HH:MM:SS + Stop button. Completed sessions listed below.
- **`EveningCheckInView`** - 3-step TabView (mood → accomplishments → AI summary). Triggers automatically when hour ≥ 19 and today's check-in isn't done yet.

### Today tab redesign
Layout (top → bottom): header → AI daily plan (time blocks) → activity rings → recovery card → FocusTimerCard → calendar events → recent workouts → nutrition

Daily plan rendered as a visual timeline - JSON array from Gemini parsed into `PlanBlock` structs with icon + color per category (morning/workout/nutrition/focus/evening).

### Bugs fixed
- `rocket.fill` SF Symbol doesn't exist on all device sets → changed `ProjectCategory.startup` to `flame.fill`
- `HKStatisticsOptions.mostRecent` typo in HealthKitService (file corruption) → fixed to `.discreteMostRecent`
- Disk 100% full causing file timeouts → cleared VSCode/Arc/Siri/Homebrew caches (~2.9 GB freed)

---

## Session 3 - Workout Import Time Fix + Delete via Context Menu

### What
- Workout import from Apple Watch now uses the Watch workout's actual start time (was showing current time)
- Workout and meal delete now works via long-press context menu

### Why (import time bug)
Two compounding bugs:
1. `GymWorkoutView` had no `prefillSession` parameter - so imported session data was ignored
2. `WorkoutsView` used `lastImportedSession()` which queried `@Query` workouts - but `@Query` doesn't update synchronously after `context.insert()`, causing a timing race where the prefill session was always `nil`

### Fix
Replaced `lastImportedSession()` with `@State private var importedSession: WorkoutSession?`. After `context.insert(session)`, immediately set `importedSession = session` and pass it explicitly to the sheet. No query timing dependency.

### Why (delete not working)
`.swipeActions` only works inside a `List`. The app uses `ScrollView + ForEach` for the Whoop-style card layout. Swipe gestures are silently ignored in this context.

### Fix
Replaced all `.swipeActions` with `.contextMenu` (long-press) on workout and meal rows. Same `context.delete()` call, different gesture.

---

## Session 4 - Workout Schedule + Planned vs Actual

### What
Weekly training template with per-day planned workout types, tracked against what was actually logged.

### Why
User wanted to see "when I was supposed to play and when I actually did" - a planned vs actual view for the whole week.

### Model
**`WorkoutScheduleEntry`** (SwiftData `@Model`):
- `dayOfWeek: Int` - Calendar weekday (1=Sun, 2=Mon … 7=Sat)
- `workoutTypeRaw: String` - stored as raw value, exposed as `workoutType: WorkoutType` computed property
- `isEnabled: Bool`

One entry per day+type combination. Toggling adds/removes entries rather than updating a flag.

### Views
- **`WorkoutScheduleEditorView`** - sheet with Mon–Sun rows, all workout types as tappable chips. Tap to add/remove a type from that day.
- **Weekly Schedule section in `WorkoutsView`** - shows the current Mon–Sun week. Each day row has: plan pills (outline), done pills (filled), and a status icon:
  - ✅ green = all planned types completed
  - ⚠️ yellow = did something but not everything planned
  - ❌ red = past day, planned but nothing done
  - dotted circle = future day, not yet scheduled

---

## Session 5 - Objective AI Coach

### What
Overhauled the Coach tab from a generic chat into a strict, data-driven performance coach that pushes back on bad decisions using actual numbers.

### Why
The old coach just said "be data-driven" in its system prompt but had no real teeth. User wanted: "if I ask if I can have an ice cream, it thinks very objectively and tells me, not just listens to me."

### System prompt overhaul (`ClaudeService.chat()`)
Core philosophy baked into the prompt:
- Never agree with a bad decision just because the user asked nicely
- Always cite specific numbers from their data
- Food decisions: check calories remaining + protein target first
- Workout skip requests: check HRV vs 7-day avg, sleep score, streak, scheduled plan - say no if data supports training
- If HRV ≥ 7-day avg AND sleep score ≥ 65, there's no objective reason to skip a planned workout
- No filler openers ("Great question!"), lead with the answer

### New ApexContext fields
- `calorieTarget` - `weight × 33` (Mifflin-St Jeor approximation for moderate activity)
- `proteinTarget` - `weight × 1.8g` (athlete standard)
- `proteinGrams`, `carbsGrams`, `fatGrams` - summed from today's MealEntry records
- `scheduledWorkoutsToday` - from WorkoutScheduleEntry for today's weekday
- `completedWorkoutsToday` - WorkoutSession records for today
- `weeklyMissedWorkouts` - count of past scheduled entries with no matching logged session
- `currentStreak` - from UserProfile
- `xpToday` - sum of xpEarned on today's workout sessions

### Coach Stance indicator
Computed from objective data, shown as a banner above the chat:

| Stance | Condition |
|---|---|
| 🔥 Full Send | HRV ≥ avg AND sleep ≥ 65 AND energy ≥ 4 |
| ⚡ Measured | 2 of 3 good |
| 🍃 Recovery | 1 of 3 good |
| 🌙 Rest Day | All indicators poor |

Live chips in the banner show "kcal left" and "protein left" for the day.

### Quick prompts updated
Old generic prompts replaced with questions that showcase objective coaching:
- "Can I have ice cream tonight?"
- "Should I skip today's workout?"
- "Am I overtraining this week?"
- "What should I eat right now?"
- "Is my recovery good enough to push hard today?"

---

## Session 6 - Streak Protection Notifications

### What
Local notification at 8pm if nothing's been logged yet, or if an active workout/meal streak is about to break.

### Why
Streaks were passive - you only found out you broke one after the fact. Needed the app to nudge before midnight instead.

### New service
**`NotificationService`** (`Services/NotificationService.swift`) - `@Observable`, no new SwiftData model:
- `requestAuthorization()` - local notification permission
- `scheduleReminderIfNeeded(profile:)` - cancels any pending reminder, then checks `lastWorkoutDate`/`lastMealDate` against today. Schedules a single 8pm notification (or ~60s out if already past 8pm) if either streak is active and unlogged today, or if nothing's been logged at all. Message text adapts to what's actually at risk.
- `cancelReminder()` - removes the pending request

### Wiring
- `GamificationService` owns a `NotificationService` and calls `cancelReminder()` at the end of `processWorkout`/`processMeal` - no point warning about something just logged
- `ContentView` requests authorization on launch (`.task`) and reschedules via `scenePhase == .background` so the reminder content is always evaluated against current streak state

---

## Session 7 - Muscle Group Tracker

### What
Recovery tracking per muscle group in the Workouts tab: last-trained date, a recovery status, and a "consider training X today" suggestion.

### Why
`GymExercise` already tagged every logged exercise with a `MuscleGroup` - that data just wasn't surfaced anywhere. Wanted gaps to be visible ("haven't done legs in 8 days") without adding a new model.

### New file
**`Utils/MuscleGroupTracker.swift`** - pure logic, no SwiftData model:
- `Status` - muscle group + last-trained date, derives `daysSinceTrained` and a `RecoveryLevel`
- `RecoveryLevel` - `.restingToday` (0-1d) → `.recovering` (2-4d) → `.neglected` (5-9d) → `.stale` (10d+ or never), each with a label + color
- `statuses(from:)` - scans gym `WorkoutSession.gymExercises`, takes the max date per muscle group, returns all 7 tracked groups sorted most-neglected first
- `suggestion(from:)` - first `.neglected`/`.stale` group, or nil if everything's been covered recently

### UI
New "Muscle Recovery" section in `WorkoutsView`, above the weekly schedule - only shown once at least one gym workout exists. Suggestion banner + full per-muscle-group list with color-coded gap text.

---

## Session 8 - Muscle Heatmap

### What
"Muscles Worked" screen (Progress tab → Muscles Worked) - a front/back body figure colored by sets logged per muscle group, with a time range picker (This Week / Last 30 Days / Since Start).

### Why
Inspired by a similar heatmap in another fitness app the user came across. Wanted set-volume, not just recovery-gap, visible directly on a body.

### Simplification vs. the reference
The reference app used a fully anatomical illustration with separately-colored quads/hamstrings/calves/traps/lats/forearms. Our `MuscleGroup` enum only has 7 broad tracked groups (chest, back, legs, shoulders, biceps, triceps, core) - extending it to finer regions would mean re-tagging every exercise in `ExerciseDatabase`. Went with a stylized figure built from simple shapes (capsules/rounded rects) where the whole leg region shares one color and forearms aren't split out from the bicep/tricep capsule. Good enough for a functional v1 - a real illustration is a design-pass candidate.

### New/changed files
- **`Utils/MuscleGroupTracker.swift`** - added `TimeRange` enum, `setCounts(from:range:)` (sums `GymExercise.sets` per muscle group within the range), and `heatColor(sets:)` (lerps between a muted cool color and `ApexColor.danger`, capped at 10 sets)
- **`Utils/Extensions.swift`** - added `Color.lerp(_:_:_:)`, a UIColor-based RGB interpolation helper
- **`Views/Progress/MuscleHeatmapView.swift`** - new screen: two `BodyFigureView`s (front/back) built from positioned shapes, a range menu, a gradient legend, and a per-group sets breakdown list
- **`Views/Progress/ProgressView.swift`** - new "Muscles Worked" nav link above the Achievements preview

---

## Upcoming / Ideas

- **Tennis match history + trends** - win rate over time, weakest drills, opponent notes
- **Home screen widget** - XP, streak, focus project visible without opening app
- **Persistent coach memory** - coach remembers past conversations across sessions, not just today's data
