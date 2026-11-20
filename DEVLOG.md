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
- `calorieTarget` - `weight × 33` (a rough rule of thumb, not Mifflin-St Jeor)
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

## Session 9 - Publish readiness

- Added MIT license, app icon, privacy manifest, local network and launch screen entries; removed the unused Health write string.
- Gemini key moved from the URL to a request header. Gemini calls require an explicit opt-in toggle in Settings. Offline, quota and Health failures show messages.
- 7 and 30 day streak bonuses are awarded. The old sleepWeek achievement became "Week of Mornings" (7 completed check-ins in a row).
- AI context says "not reported" when there is no check-in instead of a default energy of 3.
- Ollama requests now add 1,200 tokens of headroom for reasoning models. Without it `gpt-oss:20b` returned an empty reply at the 300 token meal limit.
- API key moved from UserDefaults to the Keychain, with a one-time migration of an existing key.
- Added PRIVACY.md. Removed three XP constants nothing used.
- Simulator run with Health denied showed zeros as real values and a Low recovery score. Fixed: No data, Unknown score, neutral advice. Also fixed "How was today, ?" for a user with no name.
- Health permission list was missing exercise minutes (read as 0 even with data); added it and a test.
- Found from simulator screenshots and fixed: the Nutrition Snap a Meal button wrapped its XP label one character per line; the Coach banner said Measured with no data (now No Data until a sleep or HRV reading exists). Both checked on screen, no unit test.
- Redesign (bold athletic, one blue accent, light and dark following the system): adaptive color tokens in `ApexColor`, heavy condensed titles and numbers, tracked uppercase labels, full-width section cards, blue heatmap scale, Snap a Meal uses the accent. Checked on screen in both modes; the muscle figure is still placeholder art.
- Replaced the capsule muscle figure with an original anatomical figure (pure CoreGraphics shapes, front and back).
- Heatmap scale is now blue to red; 0 sets stays neutral.
- AI providers: Gemini, OpenAI, Claude and Local, each with its own key, model and consent. One request builder and parser per provider, tested offline.
- Today is now a dashboard (next-up hero with a snapping plan carousel, quick actions, tiles that open sheets). Motion rules used: feedback is immediate, springs can be interrupted, Reduce Motion is respected, haptics only on selection. Other tabs still use the older list layout.
- A user got a 404 after adding a Gemini key and the Key saved label never changed. Added: provider error text shown in errors, a Test connection button, honest key status (Not saved yet, then Key and model updated), and an automatic model list: after a key is saved Model becomes a picker of what the key can use (free text only as a fallback). I could not reproduce the 404 without a key; Google's own pages disagree on when gemini-2.5-flash retires.
- Workouts redesigned in the dashboard style: week strip with day sheets, Train next card, last four sessions. Checked on screen in dark and light with a temporary seeded plan (removed). Nutrition, Progress and Coach still use the older layout.
- Nutrition redesigned: 7-day calorie strip, big total with a macro split bar, two log buttons. Seen in dark mode with temporarily seeded meals (removed); not seen in light mode. Progress and Coach still use the older layout.
- Progress redesigned: level hero, 14-day active strip, tiles for streaks, muscles and achievements. Seen in dark mode only. Coach still uses the older layout.
- Coach redesigned: readiness card at the top of the chat, question chips above the input. Seen in dark mode only; the chat bubbles themselves are unchanged and I have not seen a real reply. All five tabs now use the dashboard style.
- 40 unit tests on the logic layer. Still unverified: anything needing HealthKit data, a key, or a device.

---

## Session 10 - Coach Memory

### What
The coach now remembers you between conversations: your goals, lasting notes (injuries, limits, preferences) and what you talked about on earlier days.

### Why
Every chat started from zero. The coach knew today's numbers but not that you were training for something, had a sore knee, or asked the same "can I skip legs?" question two days ago.

### How it works
- **Saved chat** - new `CoachMessageRecord` model. Every question and reply is stored on device. Opening the Coach tab reloads today's conversation. Earlier days are not shown on screen; they go into the prompt as a recap.
- **Goals and notes** - new `CoachMemory` model (`goal` or `note`, text, date, whether the coach or the user added it).
- **How the coach saves something** - the system prompt asks the model to end a reply with `[remember goal: ...]` or `[remember note: ...]` when you state something lasting that isn't saved yet (at most one per reply). The app strips that line, saves it (skipping duplicates, ignoring case and punctuation) and shows a "Saved goal: ..." chip under the reply. No extra AI call.
- **What goes into each coach request** (`CoachMemoryEngine.promptSection`): up to 25 memories, goals first then newest notes, and one line per exchange for the last 3 days that had a chat (question up to 120 characters, the first sentence of the reply up to 160, at most 4 exchanges a day). Only today's messages are sent as real chat turns, capped at 20.
- **Coach Memory sheet** - brain button on the Coach tab, or the "Remembers ..." strip. Add a goal or note yourself, swipe to forget one, forget past chats, or forget everything.

### Also fixed
- "Coach offline" error bubbles used to be sent back to the model as if the coach had said them. They are now shown but never saved or sent. A question whose reply failed is merged into the next question so turns still alternate (some providers reject two user turns in a row).

### Tests
8 new unit tests: tag parsing and stripping, untagged replies unchanged, duplicate check, empty prompt with nothing saved, goals-first and the 25 cap, the 3-day recap (today and older days left out), today's turns capped and alternating, and a SwiftData round trip of both models. 48 of 48 pass on the iOS 18.0 simulator (ad-hoc signed).

Seen on the simulator: the brain button, the Coach Memory sheet, adding a goal by hand (it appears under Goals as "Added by you"), and the "Remembers 1 goal" strip on the Coach tab.

### Not checked
No chat message was sent (no key in the simulator), so saved chats and the saved chip have not been seen with a real reply. Whether real models actually emit the `[remember ...]` line reliably. That needs a real key. If a model writes it slightly differently (for example without brackets) it will show in the reply and not be saved.

---

## Session 11 - Tennis Trends

### What
A Tennis Trends screen (Progress tab card, or "Tennis trends" in the Workouts Recent header): this week's hours, a week streak, overall win rate, recent average heart rate, hours per week for 12 weeks, average heart rate per week, win rate by month for 6 months, most practiced drills, drills not practiced in 3 weeks, and a record against each opponent with the latest session note.

### How it works
- Pure logic in `Utils/TennisTrends.swift`, working on plain `Entry` values so it is tested without SwiftData. No new model; it reads `WorkoutSession` and its `TennisDetails`.
- A session is a match only when a score was logged. Sets decide it, games only when no sets were logged; equal is a draw. Drill-only sessions are not matches.
- Week streak counts back from this week; not having played yet this week does not break it.
- Opponents are matched ignoring case and extra spaces. The note shown is from the newest session against them that has notes.
- Charts use Swift Charts.

### Not possible yet
"Weakest drills" from the idea list: the app doesn't rate drills, so the screen shows drills you have stopped practicing instead. A per-drill rating in the tennis log would make this possible.

### Tests
7 new unit tests with a fixed calendar (match result rules, record and win rate, weekly buckets and heart rate mean, week streak, monthly win rate, drills counted once per session and stale drills, opponent grouping and notes). 55 of 55 pass on the iOS 18.0 simulator (ad-hoc signed).

Seen on the simulator in dark and light with 10 temporary sample sessions (removed afterwards); every number checked against the sample data. Two chart bugs found that way and fixed: the last heart rate point sat outside the plot, and a 100% win rate label ran into the card header. Installed on the iPhone; not yet seen with real sessions.

---

## Session 12 - Plan updates from your info

### What
Today's plan stays read-only, but it now follows what you tell Apex about yourself. Goals, notes (injuries, one-off appointments) and your weekly schedule feed the plan, and the plan rebuilds itself when that info changes.

### Why
The plan never saw Coach Memory or the weekly schedule, and chat about the plan was saved onto it but never read back. Telling the app "furniture shopping at 13:30 today" or "tennis weekdays at 11:30 from Wednesday" changed nothing.

### How it works
- **What the plan is built from** (`PlanUpdateEngine.inputLines`): goals and notes that apply today plus today's scheduled sessions (with time), one line each. They go into the plan request as an "ABOUT THE ATHLETE" section, with a rule to put timed commitments at their time and respect injuries.
- **Rebuild on change** - `DailyPlan.infoKeys` stores the lines a plan was built from. When Today appears, or the info changes, and they differ, the plan is rebuilt automatically. The request includes the previous plan and the time now so earlier items stay the same. The card shows "Adjusted for: ..." (what is new, or what was removed). A failed rebuild keeps the old plan on screen, says why, and isn't retried for the same info. No plan yet means no automatic call; you still tap Generate.
- **Dated notes** - `CoachMemory.validFrom/validUntil`. The coach writes `[remember note for YYYY-MM-DD: ...]` (one day), `until` or `from`. The prompt now tells it today's date. One-day notes disappear on their own the next day. In the Coach Memory sheet, notes have an "Only today" switch.
- **Schedule from chat** - `WorkoutScheduleEntry` gets an optional `startMinutes`, `startsOn` and `addedByCoach`. The coach writes `[schedule tennis: mon tue wed thu fri 11:30 from 2026-11-18]`. The app updates or adds those days and shows a chip, and sessions starting later don't count until their start date (week strip, missed count, plan). The sessions appear under "Weekly schedule from chat" in Coach Memory, where you can swipe to remove them. To drop a session, the coach tells you to use Edit plan.
- **"Something changed? Tell Apex"** on the plan card opens Coach Memory.
- Removed the old unused `userModifications` append in the coach chat.

### Tests
10 new unit tests: dated note tags, one-day notes active and then expired (and left out of the prompt), schedule tag parsing and hiding, day forms (weekdays, ranges, wrap, names), entries waiting for their start date, stable input lines and the prompt section, when a rebuild runs, the "Adjusted for" text, the date in the save instructions, and a SwiftData round trip of the new fields. 58 of 58 pass on the iOS 18.0 simulator (ad-hoc signed).

### Not checked
Not seen on screen yet, and no real model has been asked to emit the new `[remember note for ...]` and `[schedule ...]` lines. If a model writes them differently, they show in the reply and aren't saved.

---

## Session 13 - Weekly coach review

### What
A look back at each week (Monday to Sunday): the numbers, a short review from the coach, and up to two schedule changes for next week that you can accept.

### Why
Coach memory, tennis trends and plan updates each look at one day or one chart. Nothing pulled the week together or asked "did you do what you planned, and what should change?"

### How it works
- **Which week** (`WeeklyReviewEngine.reviewWeekStart`): on Sunday, the week ending today; any other day, the last full week. Weeks always start on Monday.
- **The numbers** are worked out on device, so they show without an AI key: scheduled sessions done against due (a session counts for the slot of its type on that day; today's slot counts only once done), missed sessions by day, unscheduled sessions, sessions and minutes against the week before, tennis match record and drills not practiced in three weeks, morning check-ins with average sleep score and energy, and your saved goals.
- **The coach's review** is written when you tap "Write my review" (Rewrite replaces it). The request holds only those numbers, plus the Watch's 7-day sleep and HRV averages when the review covers the week ending today. The model may end with up to two `[schedule ...]` lines starting next Monday. They are hidden from the text and shown as suggestions; nothing changes until you tap Accept, which adds the session to your weekly schedule (the same code the coach uses from chat, `WorkoutScheduleEntry.apply`). A suggestion can only add a session or set its time, never remove one.
- **Where**: Progress, Weekly review. Today shows a "Your week in review" banner on Sunday from 18:00 and on Monday until that week's review is written. A weekly reminder fires Sunday at 18:00 (only if notifications are allowed).
- **Coach chat** gets the last review and the changes you accepted for two weeks from the reviewed Monday, so it can hold you to them.
- New `WeeklyReview` model (week, text, suggestions, accepted).

### Tests
11 new unit tests: which week on Sunday, Monday, Wednesday and Saturday; when the banner shows; planned, done, missed and extra (with a slot that starts later in the week); today's session counted once done; a past week counting every day; tennis, stale drills, check-in averages and goals; the data block; parsing the reply (unknown types dropped, at most two, memory lines hidden); next Monday in the prompt; the coach section and when it stops; accepting a suggestion with SwiftData. 76 of 76 pass on the iOS 18.0 simulator (ad-hoc signed).

Seen on the simulator with no data, dark and light: the Weekly review row on Progress and the Weekly Review screen (Mon 9 to Sun 15 Nov, empty numbers, Write my review button).

### Not checked
No review has been written by a real model yet, so the wording and whether models emit the `[schedule ...]` lines, and the Accept buttons, have not been seen. Not seen with real logged weeks. The Sunday reminder has not fired.

---

## Upcoming / Ideas

- **Drill ratings** - rate each drill in the tennis log so trends can show weakest drills
- **Home screen widget** - XP, streak, focus project visible without opening app
