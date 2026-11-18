# 168: switching tabs and moving through Settings on the iPhone, measured on the phone and made quick (code)

George, 2026-11-18, after round 33: "The iPhone is still a bit slow, I notice it mostly when switching between home
tabs and when browsing/swiping around the Settings menu. Take another look using my connected iPhone if needed."
Round 33's brief 164 (`dev/briefs/ROUND-33.md`; its numbers and tools are in the notes folder, `round-33/164/`) found
that a tap is recognised at once and the time is the main thread drawing the answer, that every tab switch builds
the whole screen again (`MobileShell` builds only the tab on show), and that the phone could be installed on and
launched but not driven (UI automation was off on it). One fix landed (`PopoutController` writes only on change).
**You finish the job: the two things he names, on his phone, with numbers before and after.**

**You alone use the phone** (an iPhone 16 on iOS 26.6; its id from `xcrun devicectl list devices`). The rules of
round 33's brief 164 hold word for word: never delete the app on it; every launch of yours passes
`HITLIST_STORE_SUFFIX=r168` and `-disableCloudKit YES`; never answer a dialog on it; if it is locked or gone, work on
your simulator and say so. Your build replaces his TestFlight app; say in your report that it is installed.

**Yours**: `HITList/Views/Tabs/MobileShell.swift` and the tab screens' containers; `HITList/Views/SettingsView.swift`
and `HITList/Views/Settings/` (not `SyncEngineSettings.swift`, `ICloudCheck.swift`, `SyncLogView.swift`,
`WhatsNew.swift`; in `ICloudSettingsGroups.swift` structure only, no word, action or condition);
`HITList/Services/ResponseProbe.swift`; `HITListUITests/PhoneResponseUITests.swift`; tests of your own. A cause
elsewhere in `HITList/Views`: fix it where it is, in the smallest hunk, and list the file. **Not yours**: anything
under `Services/SyncEngine/`, core's `Sync/`, `CloudSyncMonitor.swift`, `HITListApp.swift`, the models, `project.yml`,
`scripts/`, `dev/`.

1. **A way to measure on the phone that needs nobody's finger.** First try XCUITest on the device
   (`PhoneResponseUITests`, `HITLIST_PERF=1`): George may have switched on Settings → Developer → Enable UI
   Automation. If it still refuses, make the app drive itself: a launch argument (compiled in only under a flag,
   `-D RESPONSE_PROBE`, passed as `OTHER_SWIFT_FLAGS` on the command line so no project file changes, and present
   in Debug) that switches each tab in turn several times through the shell's own state, opens Settings and each
   of its pages and comes back, and for each step writes how long the main thread worked and how long until the
   next frame was on screen, to a file in the app's `tmp`, which `xcrun devicectl device copy from` reads. **A
   Release-configuration build is what he feels**: the numbers that count are from one (`-configuration Release`
   with the flag), on the phone, with the demo week.
2. **Tabs.** Keep the screens of the tabs a person has visited alive, so a switch shows a screen that already
   exists instead of building one. This is a structural change in a file that many things lean on; what must stay
   exactly as it is: which list the "+" adds to (`popouts.listContext`, today set by the appearing list's
   `onAppear`: make it follow the tab on show, and prove it for every tab and for a pushed screen); the crossfade
   (`HITMotion.tabSwitch`) or one as quiet; a tab left and come back to shows its first screen as today, or keeps
   its place if that is what keeping it alive gives for free and nothing depends on the pop (say which, and why);
   tips and the companion show only on the tab on show; **a hidden tab does no work**: its timelines, clocks and
   animations stop (the Flipboard's breathing light, a companion, the Week layout's present-time line), and at
   rest the app's main thread is idle (measure it: a minute on each tab after visiting all four); memory after
   visiting all four with the demo week, before and after. If a kept tab cannot be made provably idle, build it
   afresh as today and keep alive only those that can.
3. **Settings.** Measure opening Settings, pushing each page, scrolling each page top to bottom, and going back.
   Round 33 found the theme swatches' seat computed on every draw (now kept, `ThemeCompanion.unitLayout`); find
   what is left: a `TimelineView` that redraws a whole page (`AccountStatusRow` has one of 30 s), rows that read
   the store or iCloud's account in `body`, sprites redrawn while scrolling, a page that builds every row up
   front. Fix what the numbers name. What a page shows and says does not change (round 33 just reworded them:
   not a word moves).
4. **The targets, on the phone, Release**: a tab already visited answers within 100 ms of main-thread work; a first
   visit within 250 ms; a Settings page pushes within 200 ms and scrolls without a frame longer than 32 ms. Where
   you cannot reach one, say what is left and where the time goes.

Each change with a test where a test can reach it (the "+" adds to the list on show after every kind of switch; a
hidden tab's clock does not tick; the shell builds a visited tab once). Proof: the table (each step, before and
after, phone Release and simulator Debug); a minute at rest per tab; `HITListTests` whole on the Mac and on your
simulator; the UI suites that walk tabs and Settings on your simulator (`HITListUITests`, `BrowseUITests`,
`SweepPolishUITests`, `SettingsTidyUITests`, `ScreenInsetsUITests`, `CompanionsUITests`, `FirstRunUITests`,
`UpcomingWeekUITests`), all of them, to the end, however long the Flipboard one takes.
