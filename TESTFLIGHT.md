# Shipping CleanSpace to TestFlight

TestFlight builds are signed with your Apple Developer team and uploaded from a Mac, so they can't be produced inside this repository. This guide takes you from the source code to testers installing the app, either through Xcode or with the included script.

## Quick start (about 15 minutes, once your account is ready)

1. **Join the Apple Developer Program** ($99/year) at developer.apple.com/programs. TestFlight isn't available with a free Apple ID.
2. **In Xcode:** select the project, set `CLEANSPACE_BASE_BUNDLE_ID` to your own ID (for example `com.yourname.cleanspace`), then choose your paid team under Signing & Capabilities for both the **CleanSpace** and **CleanSpaceWidget** targets.
3. **In App Store Connect** (appstoreconnect.apple.com): Apps › **+** › New App, with the same bundle ID.
4. **Upload:** in Xcode, set the destination to *Any iOS Device (arm64)*, then **Product › Archive** › **Distribute App** › **TestFlight Internal Only** › Distribute.
   Or in Terminal, from the project folder: `TEAM_ID=YOURTEAMID ./scripts/testflight.sh`
5. **Test:** after processing (usually 5 to 30 minutes), open TestFlight in App Store Connect, add yourself under Internal Testing, and install from the TestFlight app on your iPhone.

Two things to know before a public App Store release (they don't affect internal TestFlight):
- File sizes are read from PhotoKit's undocumented `fileSize` value on `PHAssetResource`. Many apps do this, but App Review can question it.
- "Open Photos" uses the undocumented `photos-redirect://` link. If review objects, it can be removed without affecting anything else.

## What you need

- A paid **Apple Developer Program** membership ($99/year). Free Apple IDs can't upload to App Store Connect.
- A Mac with **Xcode 16** or later, signed in under Xcode › Settings › Accounts.
- About 30 minutes for the first upload, plus Apple's processing time.

## 1. Pick the bundle ID

1. Open `CleanSpace.xcodeproj` and select the **project** (the blue icon at the top, not a target).
2. In **Build Settings**, search for `CLEANSPACE_BASE_BUNDLE_ID` and set it to something you own, such as `com.yourname.cleanspace`.

Everything else is derived from it:

| Item | Identifier |
|------|------------|
| App | `com.yourname.cleanspace` |
| Widget | `com.yourname.cleanspace.widget` |
| App Group | `group.com.yourname.cleanspace` |

## 2. Set up signing

1. Select the **CleanSpace** target › **Signing & Capabilities** › tick *Automatically manage signing* › choose your paid team.
2. Do the same for the **CleanSpaceWidget** target.
3. Xcode registers both identifiers and the App Group for you. If it shows an App Group error, click **Try Again** once. Registration sometimes lags by a few seconds.

Version numbers are set once at the project level (`MARKETING_VERSION` 1.0.0, `CURRENT_PROJECT_VERSION`), so the app and widget always match. App Store Connect rejects builds where they differ.

## 3. Create the app in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com) › **Apps** › **+** › **New App**.
2. Fill in the form:
   - Platform: iOS.
   - Name: "CleanSpace". If it's taken, try "CleanSpace Storage Cleaner".
   - Primary language: English.
   - Bundle ID: the one from step 1.
   - SKU: any text, such as `cleanspace-001`.
3. Under **App Privacy**, answer **Data Not Collected**. CleanSpace has no servers, analytics or tracking, and the included privacy manifests say the same.

## 4. Archive and upload

### Option A: Xcode

1. Set the run destination to **Any iOS Device (arm64)**.
2. Choose **Product › Archive**.
3. When the Organizer opens, choose **Distribute App** › **TestFlight & App Store** (or **TestFlight Internal Only**) › **Distribute**.
4. Before every later upload, raise the **Build** number (target › General › Identity, or `CURRENT_PROJECT_VERSION`).

### Option B: Terminal

```sh
TEAM_ID=ABCDE12345 ./scripts/testflight.sh
```

- Find your Team ID at developer.apple.com › Account › Membership details.
- The script archives a Release build and uploads it using `ExportOptions.plist`.
- It sets a build number based on the date and time, so every run is higher than the last.
- Add `BUNDLE_ID=com.you.cleanspace` to override the bundle ID without editing the project.

### Option C: GitHub Actions

`.github/workflows/testflight.yml` runs the tests and then the same script on a macOS runner. It starts when you push a `v*` tag, or you can start it manually from the Actions tab.

1. Create an App Store Connect API key under **Users and Access › Integrations › App Store Connect API**.
   - Give it the **Admin** role, so Xcode can create the distribution certificate for you.
   - Download the `.p8` file. You can only download it once.
2. Add these repository secrets:
   - `TEAM_ID`
   - `BUNDLE_ID`
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8` (the whole contents of the `.p8` file)
3. Build numbers come from the workflow run number.

## 5. After uploading

1. **Processing.** The build appears under **TestFlight** after about 5 to 30 minutes. You'll get an email if Apple finds a problem.
2. **Export compliance.** `ITSAppUsesNonExemptEncryption` is set to `NO` in `Config/Info.plist`, so App Store Connect won't ask about encryption for each build.
   - The vault uses only Apple's built-in CryptoKit (AES-GCM) to protect the user's own files on the device. Encryption provided by the operating system is generally treated as exempt.
   - Read Apple's "Complying with Encryption Export Regulations" page to confirm this for your situation. If you conclude otherwise, set the key to `YES` and answer the questions in App Store Connect.
3. **Internal testing.** Available right away, with up to 100 people from your App Store Connect team. Go to TestFlight › **Internal Testing** › **+**, add testers, and select the build. Testers install the **TestFlight** app and accept the invite.
4. **External testing.** Up to 10,000 people, by email or a public link.
   - Create a group under **External Testing** and fill in **Test Information**: what to test, a feedback email, and contact details.
   - The first build goes through Beta App Review, which usually takes about a day.
   - Apple may ask for a privacy policy URL. A simple page saying the app collects no data is enough.

### Suggested "What to test" text

> Scan your library, then try each cleanup: look-alike photos, screenshots, large videos, blurry photos, duplicate contacts and old calendar events. Try swipe mode, compress a video, and set up the private vault with Face ID. Add the CleanSpace widget to your Home Screen. Everything is analyzed on your iPhone. Deleted photos go to Recently Deleted for 30 days.

## Troubleshooting

- **"No profiles for … were found"** – Make sure both targets use the same paid team, then archive again. `-allowProvisioningUpdates` in the script lets Xcode create missing profiles.
- **App Group errors** – The App Group must be `group.` followed by your bundle ID, and both targets need it. Check it under Certificates, Identifiers & Profiles › Identifiers › App Groups.
- **"Invalid bundle: CFBundleVersion must be higher"** – Raise `CURRENT_PROJECT_VERSION`, or rerun the script, which does this automatically.
- **Missing purpose string** – The Photos, Contacts, Calendar and Face ID descriptions are in the target's build settings (`INFOPLIST_KEY_…`). Don't remove them.
- **Build fails to compile** – The project was written without access to a Swift compiler. Fix any errors in Xcode first, and make sure a normal Run to a device works before archiving.
