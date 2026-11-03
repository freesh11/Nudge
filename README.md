# Nudge — ADHD reminders, one thing at a time

SwiftUI app for iPhone (iOS 17+) with a home and lock screen widget.

**What's in it**
- **Now:** one task, its tiny first step, a big Done button, "Not yet", and "Break it down" into steps
- **Brain dump (+):** quick capture with one-tap "when" chips. "No rush" items wait unscheduled.
- **Nudges:** escalating reminders (1–5, every 5–30 min) with Done / I'm on it / 5 more min right on the notification. Tapping one opens a full-screen nudge.
- **Accountability buddy:** after the last nudge, a one-tap text to your buddy. iOS never lets apps send texts silently, so you still hit send.
- **Today:** time left until bedtime, the day's timeline, and your brain dump
- **Settings:** nudge count and spacing, bedtime, accent color, buddy, re-run setup
- **Onboarding:** 3 screens on first launch
- **Widget:** shows the current task with a working Done button. Add it to the Home or Lock Screen.

## 1. Build the .ipa (pick one)

**Option A: you have a Mac with Xcode 16+**
```
./build-ipa.sh
```
This creates `Nudge.ipa` in this folder.

**Option B: no Mac (free, uses GitHub)**
1. Create a new GitHub repo and upload this folder to it, including the hidden `.github` folder.
2. Open the repo's **Actions** tab. The "Build IPA" run starts by itself and takes about 5 minutes.
3. Open the finished run and download **Nudge-unsigned-ipa**. Unzip it to get `Nudge.ipa`.

## 2. Sign and install with your KravaSign certificate

Upload `Nudge.ipa` to KravaSign's signer, or to any on-device signer that takes your `.p12` and `.mobileprovision` (for example ESign or KSign). Sign it with your certificate, then install.

**For the widget to show your tasks:** the app and widget share data through the app group `group.com.nudge.adhd`.
- If your signer has an option to keep or merge app groups/entitlements, turn it on.
- If your provisioning profile doesn't include an app group, the app still works fully, but the widget will always say "All clear".
- If your signer changes bundle IDs, keep the widget's ID as the app's ID plus `.widget`.

## Making changes
- Edit the Swift files in `Nudge/`, `NudgeWidget/` and `Shared/`, then rebuild.
- To change the bundle ID or app group, edit `project.yml` **and** `SharedStore.appGroup` in `Shared/Shared.swift`.
