# Getting HITList onto TestFlight

Everything the build itself needs is already in the project: app icon, privacy manifest,
encryption-exempt flag, hardened runtime + sandbox for Mac, dark-only UI, CloudKit and
push entitlements, version 0.1.0 (build 1). What remains needs your Apple ID in a browser
or in Xcode, so it is listed here as a checklist.

## One-time setup (about 10 minutes)

1. **Create the App Store Connect record.** appstoreconnect.apple.com → My Apps → "+" →
   New App. Platforms: iOS and macOS. Name: HITList. Bundle ID: `com.trammells.hitlist`
   (already registered by Xcode). SKU: `hitlist`. Primary language: English (U.S.).
2. **Deploy the CloudKit schema to Production.** icloud.developer.apple.com/dashboard →
   container `iCloud.com.trammells.hitlist` → Schema → "Deploy Schema Changes…" →
   Deploy. TestFlight builds use the Production environment, and record types that only
   exist in Development will make sync fail silently. Run the Development app once first
   (simulator or iPhone) so SwiftData has created the record types to deploy.
3. **Agree to the latest agreements** in App Store Connect if it prompts you.

## Each upload

Option A, from Xcode (simplest):

```bash
open /Users/gtrammell/Desktop/HITList/HITList.xcodeproj
```

Product → Destination → "Any iOS Device (arm64)" → Product → Archive → Distribute App →
TestFlight & App Store → Upload. Repeat with destination "Any Mac" for the Mac build.
Xcode handles the distribution certificate, the production push entitlement, and symbol
upload.

Option B, from the terminal (what I verified works for archiving and signing):

```bash
cd /Users/gtrammell/Desktop/HITList
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild archive -project HITList.xcodeproj -scheme HITList \
  -destination 'generic/platform=iOS' -archivePath build/HITList-iOS.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/HITList-iOS.xcarchive -exportPath build/ios \
  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
xcrun altool --upload-app -f build/ios/HITList.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

The upload step needs an App Store Connect API key (Users and Access → Integrations →
App Store Connect API → Generate). Put the `.p8` in `~/.appstoreconnect/private_keys/`.

## Before each new build

- Bump `CURRENT_PROJECT_VERSION` in `project.yml` (build number must increase), then
  `xcodegen generate`.
- Bump `MARKETING_VERSION` when the user-facing version changes.

## After the first upload

- TestFlight → Internal Testing → add yourself. Internal builds need no review.
- Install TestFlight on the iPhone 16 and the Mac; the build appears within a few minutes
  of processing.
- Sign in to the same iCloud account on each device; data syncs through your private
  CloudKit database at no cost.
