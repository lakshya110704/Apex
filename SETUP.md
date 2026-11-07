# Apex - Setup Guide

## Prerequisites
- macOS with Xcode 15.2+ installed
- iPhone with iOS 17.0+
- Apple Watch (optional but recommended)
- Google AI Studio API key (free at aistudio.google.com/apikey)

---

## Step 1 - Create the Xcode Project

1. Open **Xcode**
2. **File → New → Project**
3. Choose **iOS → App** and click Next
4. Fill in:
   - **Product Name**: `Apex`
   - **Team**: Your Apple developer account (free or paid)
   - **Bundle Identifier**: `com.yourname.apex`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: SwiftData ✓
   - Uncheck "Include Tests" (optional)
5. Save the project **inside** this `Apex/` folder

---

## Step 2 - Replace the Template Files

Xcode creates default `ContentView.swift` and `ApexApp.swift`. Replace them:

1. In Xcode's Project Navigator, **delete** the generated `ContentView.swift` and `ApexApp.swift`
   - Choose **"Move to Trash"**
2. Right-click the `Apex` group in the Navigator → **Add Files to "Apex"...**
3. Navigate to this `Apex/Apex/` folder and select **all subfolders and files**
   - Make sure "Copy items if needed" is **unchecked** (files are already in the right place)
   - "Create groups" should be selected
4. Click **Add**

---

## Step 3 - Add Capabilities

### HealthKit
1. Click on your project in the Navigator (top item)
2. Select your **Apex** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** → search for **HealthKit** → double-click it
5. Check **Clinical Health Records** if you want (optional)

### Camera & Photos (Info.plist)
Add these keys to your `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Apex reads your workouts, sleep, heart rate, and activity data to personalize your daily plan.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Apex can save workouts to your Health app.</string>

<key>NSCameraUsageDescription</key>
<string>Apex uses the camera to photograph your meals for calorie estimation.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Apex accesses your photo library to log meal photos.</string>
```

To add them in Xcode:
1. Click `Info.plist` in the Navigator
2. Hover over any row → click **+** to add new keys
3. Type each key name above and add the description string as its value

---

## Step 4 - Get Your Google AI API Key

1. Go to **aistudio.google.com/apikey**
2. Sign up / log in (free account works)
3. Click **Create API key**
4. Copy the key (starts with `AIza`)

---

## Step 5 - Build & Run

1. Select your iPhone as the target device (plug in via USB or use wireless)
2. Press **⌘R** to build and run
3. On first launch, tap **Settings** (gear icon at top right of Progress tab)
4. Enter your name and paste your Google AI API key
5. Go back to **Today** tab - it will ask for HealthKit permissions
6. Allow all permissions for the best experience

---

## What Each Tab Does

| Tab | Features |
|-----|----------|
| **Today** | Apple Watch rings, sleep/HRV/HR stats, AI-generated daily plan, today's summary |
| **Workouts** | Log tennis (scores, drills, court) + gym (exercises with YouTube links) |
| **Nutrition** | Snap a meal photo → the AI estimates calories + macros instantly |
| **Progress** | XP level, streaks, all-time stats, achievements grid |
| **Coach** | Chat with the AI coach to adjust your plan or ask fitness/nutrition questions |

---

## Gamification XP Values

| Action | XP Earned |
|--------|-----------|
| Log gym workout or run | +60 XP |
| Log tennis session | +80 XP |
| Log other workout | +30 XP |
| Log a meal | +25 XP |
| 7-day workout streak (once, when reached) | +250 XP |
| 30-day workout streak (once, when reached) | +1,000 XP |
| Unlock achievement | +25 to +750 XP (per achievement) |

Not awarded: completing the daily plan, closing activity rings and logging sleep. The values exist in `Constants.swift` but nothing calls them.

---

## Troubleshooting

**HealthKit data shows zeros:**
- Make sure you approved all HealthKit permissions
- Go to Settings → Health → Data Access → Apex and ensure all are enabled
- Sync your Apple Watch so data is on iPhone

**Meal analysis not working:**
- Check your Google AI API key in Settings
- Make sure you have API credits (free tier has a limit)
- Try a clearer photo with good lighting

**Build errors:**
- Make sure iOS deployment target is set to **17.0** in Build Settings
- Clean build folder: **⌘⇧K**, then build again with **⌘R**

---

## Future Features to Add
- [ ] Workout templates (push/pull/legs split)
- [ ] Weekly AI review
- [ ] Apple Watch companion app
- [ ] Run tracking with GPS
- [ ] Water intake tracking
- [ ] Body weight / measurement logging
- [ ] HealthKit workout write-back
