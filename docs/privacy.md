---
title: HITList Privacy Policy
permalink: /privacy/
---

# HITList Privacy Policy

Effective 2026-11-11.

## Who we are

HITList is a task list app for iPhone, iPad and Mac made by George Trammell. It is in beta and is
distributed through Apple's TestFlight. In this policy "we" means George, the developer.

## What we collect

Nothing. HITList has no account system of its own, no servers, no analytics, no advertising and no
crash-reporting service. The app does not send your tasks, your profile or anything about how you use it
to us or to anyone else. There is no server of ours for it to contact. The only way tasks leave your iCloud
is the optional Claude connection described below, which you switch on and connect yourself, and the optional
Shared Tasks lists, which you share with people you invite.

## Where your data lives

Your tasks, Groups, labels, saved filters and your profile are stored on your device and in your own
iCloud account, in HITList's private iCloud database. Apple keeps that database; we cannot see it, read
it or reach it. It syncs to every device signed in to the same Apple account. If you are not signed in to
iCloud, your data stays on the device. Apple's handling of iCloud data is covered by
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

## Your profile

The name and picture you set in Settings → Account are stored the same way as your tasks: in your iCloud
private database, visible only to you on your own devices. The picture is shrunk on your device (512
pixels at most) before it is saved.

## Claude (optional, off unless you turn it on)

HITList can let Claude, Anthropic's assistant, work with your tasks. It is off and hidden until you switch on
Settings → Claude → Claude integration and, on a Mac, connect Claude Desktop or Claude Code yourself. While it is on and HITList
is open, the Claude app on your Mac can list, add, complete and edit the tasks your privacy setting allows
(everything except tasks labelled `@private`, or only tasks labelled `@claude`); hidden tasks are never shown
to it. What Claude does with what it reads is covered by Anthropic's terms and privacy policy, between you and
Anthropic: HITList sends nothing to us or to Anthropic on its own. With the integration on, "Copy for Claude" only
puts the allowed tasks on your clipboard for you to paste wherever you choose.

## Shared Tasks (optional preview, off unless you turn it on)

If you switch on Shared Tasks (Browse → Shared Tasks) and create or join a shared list, that list's tasks are
stored in the list owner's iCloud account using Apple's CloudKit sharing, and everyone the owner invites can see
and change them. Each member's HITList profile name and picture, and who added or completed each task, are visible
to the other members of that list. HITList has no server of its own here either: the lists move only between the
members' devices through Apple's iCloud. Leaving a list removes your access; the owner can remove members or stop
sharing at any time. Switching Shared Tasks off keeps your lists in iCloud.

## Siri and Shortcuts

HITList's Siri phrases and Shortcuts actions run on your device and use the same data as the app. What you say
to Siri is handled by Apple under Apple's privacy policy.

## Calendar events (optional, off unless you turn it on)

If you switch on Settings → General → Calendar events, HITList asks for access to your calendars and shows the
events of the calendars you pick beside your tasks in Today and Upcoming. It only reads them: it never adds,
changes or deletes an event. The events are read on the device each time they are shown and never leave it:
they are not saved with your tasks, synced through iCloud, put in backups or exports, shown in Spotlight or
Siri, or given to Claude. Switching it off stops the reading; you can also withdraw access in your device's
settings under Privacy & Security → Calendars.

## Your companion's local time and weather (optional, asked once)

The first time you open HITList, it asks once to use your location while the app is in use, and only an
approximate one (about the size of a town). It uses it for two things only: to keep your companion on local time
where you are, and to dress it for the weather there. If you choose Don't Allow, nothing else changes, HITList
does not ask again, and your companion keeps your device's time without weather.

When the app comes to the front, at most once an hour, HITList gets that approximate location from your device
and makes two requests with it, both handled by Apple under [Apple's Privacy
Policy](https://www.apple.com/legal/privacy/): it asks Apple Weather (WeatherKit) whether it is raining, snowing,
stormy, cloudy or clear there, and it asks Apple's map service (the reverse geocoder in MapKit) which time zone
that place is in. HITList shows no forecast, temperature or place name. The location is never stored, synced
through iCloud, logged, put in backups or exports, or sent anywhere else; the sky and the time zone are kept in
memory only and forgotten after three hours. Your tasks, reminders and lists always follow your device's own time
zone, never this one.

Settings → Extras → Weather switches it off, and with it off, without permission, or with Companions off, HITList
makes no location, weather or map request at all. You can also withdraw the permission in your device's settings
under Privacy & Security → Location Services → HITList.

## Notifications

Reminders, the morning summary and the app badge are scheduled by the app on your device with Apple's
notification system. HITList asks for permission only when you turn one of them on. Nothing about your
reminders leaves the device apart from your tasks syncing through iCloud as described above.

## Backups and exports

HITList keeps a daily backup file of your tasks in the app's own folder on your device (on iPhone and iPad
you can see it in the Files app under On My iPhone → HITList; it is part of your device backup like other
app files). Export JSON writes a file wherever you choose. These files are yours: the app never uploads
them anywhere.

## Diagnostics and the sync log

Settings → About → Copy diagnostics puts a short text on your clipboard: the app version and build, your
device model and system version, the iCloud sync state and the last sync times, the iCloud environment, the
app's storage location on the device, whether notifications are allowed and switched on, and whether a
profile exists and has synced (never its name or picture). Settings → iCloud → Sync log records sync
activity on the device (counts, record types, times and error codes; never task titles or other content).
Neither is ever sent by the app: they reach us only if you copy, share or save them and send them yourself.

## Beta feedback

On iPhone and iPad, Profile → Send Beta Feedback… opens a new email to the developer in your mail app, with the
app's version and build, your device model (such as "iPhone17,3", never its name) and system version filled in at the
bottom. On a Mac it only copies the developer's email address to your clipboard. Nothing is sent unless you send an
email yourself, and it contains nothing from your tasks or profile unless you type it.

## TestFlight

While HITList is in beta, Apple's TestFlight shares with us the crash reports, screenshots and feedback you
choose to send with Send Beta Feedback, plus the information Apple describes in its
[TestFlight terms](https://www.apple.com/legal/internet-services/itunes/testflight/sren/terms.html), such as
your name and email address as a tester, which builds you installed and how many sessions you had. We use it
only to fix and improve HITList.

## Children

HITList is not directed at children under 13 and we do not knowingly collect information from anyone,
children included.

## Deleting your data

Signing out of iCloud or deleting the app never deletes your iCloud data. To delete it, remove HITList's
data from iCloud: on iPhone or iPad, Settings → [your name] → iCloud → Storage (on iOS 18: Manage Account
Storage) → HITList → Delete Data from iCloud; on a Mac, System Settings → [your name] → iCloud → Manage →
HITList → Delete from iCloud. Settings → Account → Delete profile removes only your profile name and
picture.

## Changes to this policy

If this policy changes, the new version is posted on this page with a new effective date. The history of
every change is in the app's public repository.

## Contact

Use Send Beta Feedback in TestFlight, or open an issue at
[github.com/Aeronyx/HITList/issues](https://github.com/Aeronyx/HITList/issues).
