# Brief 53: version, changelog and beta feedback in the profile menu (branch `profile-feedback`, effort High)

Read `briefs/COMMON.md` (Round 11 block, "Seeing the Mac app" and "Driving the iPhone app") and `briefs/HIG-NOTES.md`.
Sessions 54–56 run at the same time. This is the last build before George invites friends (TestFlight group "Friends").

George's words, 2026-11-05:

> Add a version number + small changelog popout and beta feedback option under the Profile dropdown for users to
> see. It can go to my email (george@trammells.com).

## Items (one commit each, failing test first where there is logic)
1. **Profile menu** (Mac sidebar `ProfileMenu`; iPhone/iPad: the profile button at Browse's top left becomes the same
   menu instead of jumping straight to Settings): Account settings… · What's New · Send Beta Feedback… · a quiet
   version line at the foot ("HITList 0.7.0 (17)", from `AppInfo`). Custom design-system menu, as the Mac one is now.
2. **What's New popout** (new `Views/Account/WhatsNewPopout.swift`): a small card/popover with the current version's
   entries from `WhatsNew.entries` (read only; `WhatsNew.swift` is the supervisor's) and "Earlier versions" expanding
   the rest. Popover on Mac/iPad, a medium sheet on iPhone. Dark slate, `HITType` roles.
3. **Send Beta Feedback** (new `Views/Account/BetaFeedback.swift`): opens Mail with `mailto:george@trammells.com`,
   subject "HITList beta feedback — 0.7.0 (17)", body ending with a short footer (app version and build, device model,
   OS version, platform; never task content, names or ids). If no mail client can open it (iPhone without Mail), show
   a small card with the address and a Copy button. Mention TestFlight's own screenshot feedback in one line there.
4. Tests for the mail URL (encoding, footer contents, nothing private) and the menu's items per platform.

## Ownership
`Views/Account/ProfileMenu.swift`, `Views/Tabs/BrowseView.swift` (the profile button only), new
`Views/Account/WhatsNewPopout.swift`, `Views/Account/BetaFeedback.swift`; tests `ProfileMenuTests`, new
`BetaFeedbackTests`; ROADMAP row "Profile menu: version, What's New, beta feedback (brief 53)". Not yours:
`WhatsNew.swift` (read only), `SyncStatusViews.swift` (54), `ClaudeSettingsSection.swift` (55), `Views/Tips/*` (56).

## Done
All three suites green; a UI test (`HITListUITests`) that opens the iPhone menu, What's New and the feedback card,
with screenshots; a capture of the Mac menu and popout via `scripts/window-shot.sh`/`window-drive.sh`.
