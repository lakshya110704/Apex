# Apex

A native iOS personal agent app. It reads your Apple Watch health data, logs workouts and meals, generates an AI daily plan, and pushes back on you like an objective coach — not a cheerleader.

No backend. SwiftUI + SwiftData, offline-first, all AI calls go straight from the device to Gemini.

## Why

Most fitness/tracking apps show you charts. Apex is meant to actually *use* the data — HRV, sleep, activity rings, training history, calendar, GitHub activity — and turn it into a daily plan and a coach that argues with you using your own numbers instead of just agreeing with whatever you ask.

## Features

| Tab | What it does |
|---|---|
| **Today** | Activity rings, sleep/HRV/HR stats, AI-generated daily plan as a visual timeline, focus timer, calendar events, recent workouts/nutrition |
| **Workouts** | Log tennis (scores, drills, court) and gym sessions; weekly planned-vs-actual training schedule |
| **Nutrition** | Snap a meal photo → AI estimates calories + macros |
| **Progress** | XP, levels, streaks, all-time stats, 15 achievements |
| **Coach** | Chat that cites your actual numbers (calories left, protein left, HRV vs. 7-day avg, sleep score) and says no to bad decisions when the data doesn't support them |

Also: morning/evening check-ins, gamified XP for logging things, GitHub commit tracking, EventKit calendar integration.

## Stack

- **SwiftUI + SwiftData** — native, offline-first, no backend
- **HealthKit** — Apple Watch data: sleep, HRV, resting HR, VO2 max, activity rings, workouts
- **EventKit** — today's calendar events
- **Gemini 2.5 Flash** (Google AI API) — meal photo analysis, daily plan generation, coach chat
- **XcodeGen** (`project.yml`) — the `.xcodeproj` is generated, not hand-edited or committed as a binary

## Project structure

```
Apex/
  Models/     SwiftData @Model classes (UserProfile, WorkoutSession, MealEntry, DailyPlan, ...)
  Services/   HealthKitService, ClaudeService (Gemini), GamificationService, CalendarService, GitHubService, FocusTimerService
  Views/      One folder per tab: Today, Workouts, Nutrition, Progress, Coach, Morning, Evening, Settings, Components
  Data/       Static exercise database
  Utils/      Constants, extensions
```

The AI context assembled for every request lives in `ApexContext` (`Services/ClaudeService.swift`) — a single struct bundling health, recovery, training history, nutrition, calendar, and GitHub data so the AI always reasons from real numbers.

## Getting started

See [SETUP.md](SETUP.md) for the full walkthrough (Xcode project creation, HealthKit capability, Info.plist keys, Gemini API key, build & run).

Quick version:
1. Xcode 15.2+, iOS 17.0+ device, a free Gemini API key
2. `xcodegen generate` (or open the existing `.xcodeproj`)
3. Build & run, then add your name + API key in Settings

## Project history

[DEVLOG.md](DEVLOG.md) has the full session-by-session history — architecture decisions, bugs and their root causes, and what's planned next.

## Status / roadmap

Actively developed. Near-term ideas (from DEVLOG): muscle group tracking, tennis match trends, streak-protection notifications, a home screen widget, persistent coach memory across sessions.
