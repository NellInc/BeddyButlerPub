# Privacy

Beddy Butler stores its schedule, voice, volume, onboarding, and pause settings locally in macOS preferences. It does not collect analytics, create an account, contact a server, or transmit the bedtime schedule.

The **Beddy Butler Website** command opens beddybutler.com in the default browser. **Send Feedback** opens the project's GitHub issue form. Any information subsequently shared with either site remains under the user's control and is governed by that site's privacy terms.

Voice recordings are bundled with the application and play locally. Beddy Butler does not request microphone access.

Visual nudges use the local menu-bar icon and preferences window. They remain visible across relaunches until acknowledged. Users can optionally enable silent local Notification Center alerts; Beddy Butler requests macOS notification permission only when that option is enabled. These alerts are created locally and do not contact a notification server.

## Release verification

Each release should confirm that:

1. The App Sandbox remains enabled.
2. No network client entitlement is present.
3. No telemetry or crash-reporting dependency has been introduced.
4. Notification permission is requested only after an explicit user choice and visual badge delivery still works when permission is declined.
5. This notice still describes the shipped binary accurately.
