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
- **Ollama (optional)**. If you enter a LAN address in Settings and it responds, text requests go to your own Ollama server instead. Meal photo analysis always uses Gemini.
- The class is named `ClaudeService` for historical reasons. It does not call Anthropic.

Gemini calls are off until you turn on "Share data with Google Gemini" in Settings. The key is stored in `UserDefaults` on the device (not the Keychain), is sent in a request header, and is never part of the source.

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
- Unit tests: 20 run, 20 pass, 0 fail (iOS 18.0 simulator, `xcodebuild test`). They cover the data and logic layer only: levels, streaks, XP, achievements, muscle tracker, exercise list, meal JSON parsing, AI consent gate and error messages.
- Not covered by tests and not verified by me: HealthKit and Apple Watch data, the 8pm notification, camera, calendar, GitHub, and real Gemini or Ollama calls. These need a device, a key or a local server.
- Not awarded: XP for completing the daily plan, closing rings and logging sleep (constants exist, nothing calls them).
- The calorie and protein targets are rough rules (weight x 33 kcal, weight x 1.8 g), not a validated formula, and are 0 when Health has no weight.
- The sleep score is a simple home-made formula from sleep hours and HRV.
- Not yet done for an App Store release: privacy policy URL, support URL, App Store listing and TestFlight setup (needs an Apple Developer account and a team ID).

History and design notes are in [DEVLOG.md](DEVLOG.md).

## License

MIT, see [LICENSE](LICENSE).
