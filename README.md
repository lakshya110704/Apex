# Apex

A native iOS app that combines Apple Watch health data, workout and meal logging, an AI daily plan and a chat coach. SwiftUI + SwiftData, no backend of its own.

## Features

| Tab | What the code does |
|---|---|
| **Today** | Activity rings, sleep / HRV / resting HR, AI-generated daily plan shown as a timeline, focus timer, today's calendar events, recent workouts and meals |
| **Workouts** | Log tennis and gym sessions, import workouts from Apple Watch, weekly planned vs actual schedule, muscle recovery list |
| **Nutrition** | Log a meal from a photo or a text description and get calorie and macro estimates from the AI |
| **Progress** | XP and level, workout and meal streaks, all-time stats, achievements, "Muscles Worked" heatmap (sets per muscle group) |
| **Coach** | Chat with the AI. The system prompt tells it to answer from your numbers (calories and protein left, HRV vs 7-day average, sleep) |

Also: morning and evening check-ins, XP for logging, a local notification at 8pm when a streak is at risk or nothing is logged, GitHub commits for today (public events API, username set in Settings).

## AI services

- **Gemini** (`gemini-2.5-flash`, Google AI REST API). Needs your own API key, entered in Settings. Used for meal analysis, daily plan and coach chat. Meal photos and the health/context summary are sent to Google when you use these features.
- **Ollama (optional)**. If you enter a LAN address in Settings and it responds, text requests go to your own Ollama server instead. Meal photo analysis always uses Gemini. Ollama requests get 1,200 extra tokens so reasoning models such as `gpt-oss:20b` do not use the whole limit on hidden thinking and return an empty reply. I checked this with the same request shape sent by `curl` to `gpt-oss:20b` (valid JSON back at a 1,500 token limit, empty reply at 300). I have not run the app itself against an Ollama server.
- The class is named `ClaudeService` for historical reasons. It does not call Anthropic.

Gemini calls are off until you turn on "Share data with Google Gemini" in Settings. The key is stored in the iOS Keychain on the device, is sent in a request header, and is never part of the source.

## Stack

- SwiftUI, SwiftData (iOS 17+)
- HealthKit (read only), EventKit (calendar, read only), UserNotifications
- XcodeGen (`project.yml`) to generate `Apex.xcodeproj`

## Project structure

```
Apex/
  Models/     SwiftData models and enums
  Services/   HealthKitService, ClaudeService (Gemini + Ollama), GamificationService, CalendarService, GitHubService, FocusTimerService, NotificationService
  Views/      One folder per tab plus Morning, Evening, Settings, Components
  Data/       Exercise and tennis drill lists
  Utils/      Constants, extensions, MuscleGroupTracker
```

## Getting started

See [SETUP.md](SETUP.md). In short: Xcode 15.2 or newer, an iOS 17+ device (HealthKit data needs a real device), and a free Google AI Studio API key.

```bash
xcodegen generate   # optional, the .xcodeproj is committed
open Apex.xcodeproj
```

Add your name and API key in Settings on first launch.

## Status

- Builds with Xcode 27.2 for the iOS 18.0 simulator.
- Unit tests: 24 run, 24 pass, 0 fail (iOS 18.0 simulator). Run them ad-hoc signed, because the Keychain test needs an entitlement that unsigned builds lack: `xcodebuild test -project Apex.xcodeproj -scheme Apex -destination 'platform=iOS Simulator,name=<your simulator>' CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO`. With `CODE_SIGNING_ALLOWED=NO` the Keychain test fails (last unsigned run: 21 tests, 4 failures, all that test). They cover the data and logic layer only: levels, streaks, XP, achievements, muscle tracker, exercise list, meal JSON parsing, AI consent gate, error messages, Keychain storage and migration, and missing-Health-data handling, and that every Health type the app reads is in the permission list.
- Not covered by tests and not verified by me: HealthKit and Apple Watch data, the 8pm notification, camera, calendar, GitHub, and real Gemini or Ollama calls. These need a device, a key or a local server.
- No XP for completing the daily plan, closing rings or logging sleep.
- The calorie and protein targets are rough rules (weight x 33 kcal, weight x 1.8 g), not a validated formula, and are 0 when Health has no weight.
- The sleep score is a simple home-made formula from sleep hours and HRV.
- Seen on a simulator screen (iOS 18.0): app icon, first-run Health and notification prompts, the check-in with Health denied. Not seen: the Settings toggle and the Today notice.
- Not yet done for an App Store release: a hosted privacy policy URL (the text is in PRIVACY.md), a support URL (the GitHub issues page can serve), App Store listing and TestFlight setup (needs an Apple Developer account and a team ID).

History and design notes are in [DEVLOG.md](DEVLOG.md).

## Privacy

See [PRIVACY.md](PRIVACY.md).

## License

MIT, see [LICENSE](LICENSE).
