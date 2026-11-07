# Apex Privacy Policy

Last updated: 2026-11-07

Apex is a personal app. It has no account, no developer server, no analytics, no advertising and no tracking. This policy says what the app reads, where it goes and how to stop it.

## What stays on your device

Apex stores your name, XP and streaks, workouts, meals (including meal photos), daily plans, check-ins and focus sessions in an on-device database. Your Google AI key is stored in the iOS Keychain on this device only. Nothing here is sent to the developer.

## What the app reads

- **Apple Health (read only):** workouts, heart rate, resting heart rate, heart rate variability, active and basal energy, steps, walking and running distance, sleep, activity rings, VO2 max, respiratory rate, body weight and mindful minutes. Apex never writes to Health.
- **Calendar:** today's event titles, times and calendar names.
- **Camera and photo library:** only the meal photos you choose to take or pick.
- **GitHub (optional):** if you enter a username in Settings, Apex asks GitHub's public events API for that account's commits today. Only the username is sent.

You can turn off any of these permissions in iOS Settings.

## What is sent to Google (only if you allow it)

AI features are off until you turn on "Share data with Google Gemini" in Settings and add your own Google AI API key. When on, and when you use an AI feature (daily plan, coach chat, meal analysis), Apex sends a request to Google's Gemini API containing some or all of:

- a summary of your health and activity numbers listed above
- your logged workouts and meals for the day
- today's calendar event titles and times
- GitHub commit counts and repository names, if configured
- your chat messages
- meal photos or meal descriptions you submit

Requests use your own API key, so Google handles this data under the terms that apply to that key. Please read Google's terms for the Gemini API. The developer of Apex does not receive this data.

## Optional local AI

If you enter an Ollama server address in Settings, text requests (coach, daily plan, text meal estimates) go to that server on your own network instead of Google. They contain the same kinds of data as above. Meal photo analysis always uses Google Gemini.

## Not medical advice

Calorie, macro, recovery and coaching output is an AI estimate based on the data you log. It is not medical, dietary or professional advice.

## Your controls

- Turn off "Share data with Google Gemini" in Settings at any time. No request goes to Google Gemini while it is off.
- Remove your API key by clearing the key field in Settings and saving.
- Delete a workout or meal by long-pressing it in the app.
- Deleting the app removes the on-device database.
- Data already sent to Google is outside the app's control; see Google's terms.

## Children

Apex is not directed at children.

## Contact and changes

Questions or issues: https://github.com/lakshya110704/Apex/issues. If this policy changes, the date above changes and the new version is published in this repository.
