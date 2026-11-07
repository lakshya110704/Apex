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

## What is sent to your AI provider (only if you allow it)

AI features are off until you pick a provider in Settings, add your own API key and turn on sharing for that provider. You can choose Google Gemini, OpenAI or Anthropic Claude. When sharing is on, and when you use an AI feature (daily plan, coach chat, meal analysis), Apex sends a request straight from your phone to the provider you chose, containing some or all of:

- a summary of your health and activity numbers listed above
- your logged workouts and meals for the day
- today's calendar event titles and times
- GitHub commit counts and repository names, if configured
- your chat messages
- meal photos or meal descriptions you submit

Requests use your own API key, so the provider handles this data under the terms that apply to that key. Please read the provider's terms. The developer of Apex does not receive this data. Sharing is a separate switch for each provider, and each one is off until you turn it on.

## Optional local AI

If you choose Local (Ollama) and enter a server address, text requests (coach, daily plan, text meal estimates) go to that server on your own network instead of a cloud provider. They contain the same kinds of data as above. Meal photo analysis is not available with a local model.

## Not medical advice

Calorie, macro, recovery and coaching output is an AI estimate based on the data you log. It is not medical, dietary or professional advice.

## Your controls

- Turn off sharing for a provider in Settings at any time. No request goes to that provider while it is off.
- Remove a provider's API key by clearing its key field in Settings and saving. Keys are stored in the iOS Keychain on this device only.
- Delete a workout or meal by long-pressing it in the app.
- Deleting the app removes the on-device database.
- Data already sent to a provider is outside the app's control; see that provider's terms.

## Children

Apex is not directed at children.

## Contact and changes

Questions or issues: https://github.com/lakshya110704/Apex/issues. If this policy changes, the date above changes and the new version is published in this repository.
