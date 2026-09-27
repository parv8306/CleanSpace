# CleanSpace

CleanSpace is an iPhone storage cleaner. It finds look-alike photos, screenshots, large videos, blurry photos, duplicate contacts and old or duplicate calendar events, and removes only what you approve. It can also compress big videos instead of deleting them, and keep private photos in a passcode-locked vault. Everything runs on the device. There are no servers, no accounts, no analytics and no payments.

Built for the App Factory internship assignment (reference app: "Cleanup: Phone Storage Cleaner"). The name, icon, palette and copy are original.

## What's new in 1.0.0

- **New name and identity.** The app is now **CleanSpace**: "Make room for what matters." A new icon (an open "C" that holds water, with a sparkle) and a blue design system with light and dark palettes replace the old teal look.
- **Redesigned dashboard.** A large water gauge fills to your real used storage when the screen appears, with gently moving water and a percentage that stays readable above and below the waterline. The part CleanSpace can free shows as a lighter aqua band. Used, Free and Can free figures sit underneath, followed by category cards with icons, sizes and share bars.
- **Scan button.** A prominent gradient button that says "Scan My iPhone" before the first scan and "Scan Again" after, with an idle pulse and shimmer. While scanning, its icon spins, it shows real progress, duplicate taps are ignored, and a live card lists each stage as it actually runs and finishes. A light sweeps around the gauge rim during a scan.
- **Cleanup animation.** After a cleanup, the removed items gather into the center, a blue swoosh sweeps around, a check appears with a light burst, and the freed space and item counts count up from zero. A small gauge shows storage before and after (once Recently Deleted is emptied). Every number comes from the actual deletion results.
- **Settings rebuilt.** Every Access row is a working control with a clear status badge (granted, limited, denied, restricted, not asked). Tapping explains and asks, offers "Select more photos" for limited access, or opens CleanSpace in the Settings app. Status refreshes when you come back. New: a weekly scan reminder (a local notification), Clear temporary files, About, What's New, Privacy Policy, Terms of Use, Rate CleanSpace, and version and build. "Show welcome again" is gone.
- **Polish.** Pulsing scanner loading states, illustrated empty states with clearer wording, springy checkboxes with haptics, press feedback on cards, and staggered card entrances. All motion respects Reduce Motion and pauses off screen.

### Scanning, categories and appearance (1.0.0 update)

- **Every accessible photo is scanned.** The photo fetch now includes every burst frame (PhotoKit returns only a burst's key photo by default). When no high-quality preview is on the device, a smaller local preview is used instead of skipping the photo, and any photo that still can't be analyzed is counted and reported. There were no count or size caps; processing runs in memory-safe batches of 64 thumbnails, never full-resolution images. Hidden-album photos stay excluded on purpose, out of respect for the Hidden album.
- **Duplicate Photos vs Similar Photos.** Candidates with identical visual fingerprints and dimensions are confirmed as exact copies by a SHA-256 hash of the photo's file, streamed from the device. When the file isn't on the device, a hash of the decoded pixels is used instead. Confirmed copies form Duplicate Photos; only one copy of each set stays in Similar Photos, so extras are never listed twice.
- **Chat Photos (best effort).** iOS doesn't record which app saved a photo, so CleanSpace uses file names (for example `-WA0012`, `telegram`, `received_…`, `signal-…`, `mmexport…`) to attribute a platform, and a compression footprint (JPEG, no location, long edge exactly 1600, 1280 or 2560 px) for "Other chat apps". The UI says "likely", and platforms appear only with file-name evidence. Photos sent through iMessage can't be detected. `ChatPhotoDetector` is unit-tested.
- **Large Videos** now means every video of 25 MB or more, largest first.
- **Dashboard.** A segmented, glowing storage ring around the water orb, with Used, Free and Total, and a headline for what can be freed. Scan Again has a custom radar icon that sweeps while scanning and pings when tapped. Six primary cards (Duplicate Photos, Similar Photos, Screenshots, Chat Photos, Large Videos, Duplicate Contacts) with short descriptions, plus Blurry Photos and Calendar Events under More.
- **Category information.** Tapping a card opens a bottom sheet explaining the category, what was found, and, for swipeable categories, an animated demo of the real gestures: left marks for deletion, right keeps. "Don't show this again" is per category, and an info button inside each category reopens it. Swipe mode shows the demo on first use and from its "?" button.
- **Detail footer.** Selected count, how much can be freed, and a Review Cleanup button.
- **Vault PIN.** Glowing vault header, six PIN boxes with fill animation, two-step create and confirm with slide transitions, a red shake state when PINs don't match, and haptics. The PIN is stored only as a salted PBKDF2 hash in the Keychain.
- **Appearance.** System, Light or Dark in Settings, saved across launches and applied to every screen, sheet and system picker by overriding the window's interface style. All colors are defined for both modes in `Theme` (also available as `CleanSpaceTheme`).

### Design system and screen polish

- **Design system.** `Theme` (alias `CleanSpaceTheme`) holds colors for light and dark, typography, spacing (4 to 32), a three-step radius scale (10, 16, 24), shadows, gradients and animation timing. Shared components in `CleanSpaceShared/DesignSystem.swift`: `CleanSpaceIcon`, `SectionHeader`, `SelectionBadge`, `CleanSpaceButton` (primary, secondary, destructive), `glassCard()`, `PrivacyCard`, and a staggered `entrance` modifier. Brief names such as `ScanButton`, `StorageVisualization` and `CleanupSuccessView` map to the implementing views.
- **Dashboard.** Used space in GB inside the water orb, Used and Free underneath, then how much can be freed. The header, storage, scan button and each card enter in sequence. While scanning, each stage shows a real progress bar. Also a "Last scanned: Today at 9:42 AM" line and a privacy card.
- **Selection is blue everywhere.** Blue outline and checkmark on grid and group thumbnails, with a subtle scale; the recommended photo in a group is outlined in green with a Keep badge and a "Recommended to keep" line. Red is reserved for Delete, Stop and errors.
- **Contacts.** "Possible duplicate" cards with overlapping avatars, name, first phone and email, why they matched, and the planned action.
- **Review Cleanup.** A summary card lists what you selected by type, with the estimated space freed.
- **Cleanup animation.** Thumbnails of the photos being removed are captured before deletion and fly into the swoosh.
- **Vault.** Blue-to-navy backdrop, glass cards, a smooth transition and success haptic when the vault opens.
- **About.** Your-privacy card, features, Privacy Policy and Terms pages, Rate CleanSpace, Send Feedback (once `AppInfo.feedbackEmail` is set) and the version.

### Glass popups, real compression, visual history

- **Popups.** Every popup (category info, previews, review, permissions, settings pages, vault viewer, compression, swipe help) opens full screen, sliding up from the bottom, on a frosted glass material with a light tint for readability. A grab handle at the top drags down to dismiss; popups without their own Done button also get a close button. Flows that must not be interrupted (Review while deleting, compression) have no drag handle. System confirmation dialogs and alerts are drawn by iOS and keep the system style.
- **Video compression, rebuilt.** The old version used AVAssetExportSession presets, which choose their own bitrate, so the result couldn't follow a target size and 1080p sources often barely shrank. It now re-encodes with AVAssetReader and AVAssetWriter at an explicit bitrate computed from the chosen target (High about 60%, Balanced about 35%, Smallest about 20% of the original, with a floor for watchable quality), at a resolution that suits that bitrate. HEVC is used when available, H.264 otherwise; HDR is converted to standard range through a video composition; audio is stereo AAC. After encoding, the file is opened and checked to be playable and full length before it's saved. The screen shows original, target and compressed sizes, live progress, and lets you play the compressed copy. `CompressionEstimator` is unit-tested.
- **Cleanup History with thumbnails.** On the Review screen, before anything is deleted, CleanSpace captures a small JPEG of each item (up to 60 per cleanup) and keeps only those iOS confirmed as deleted. History shows them in a grid, with video lengths, "+N more" beyond the limit, and a detail view with date and size. Thumbnails stay on the device and are removed when history is cleared. Records from earlier versions show text only.
- **Scan completion.** Finishing a scan no longer selects anything, so the dashboard shows no "selected" badges and no Review bar until you choose. Suggested picks for Duplicate and Similar Photos are applied the first time you open that category (or when a scan finishes while it's open). Swipe mode starts with nothing selected and drops the suggestions.
- **Dashboard.** The segmented ring and rim sweep, which looked like a loading indicator, are gone. The water orb now rests in a still glass disc with a soft halo. Blues are softer and brighter, shadows lighter, and cards have a subtle glass edge. Scan Again is a compact pill (about 56 pt tall) with inline progress; Review Changes is a smaller capsule.

### Popups with real examples, battery, faster launches

- **Popups.** Category popups open with real examples from the person's library (duplicate pairs with the copy to keep, look-alike pairs with the best shot, screenshot and chat-photo grids, the largest videos with sizes, a duplicate contact card, old events), then the title, the explanation in a glass panel, what was found, the swipe demo and a "Let's Go" button.
- **Selection bar.** One line ("12 items selected, 1.2 GB"), a clear button and a compact Review Changes button.
- **Photo cards.** White pills with dark text over a soft shade, so they read clearly on any photo. Duplicate Contacts shows a contact card with the person's photo or monogram.
- **Battery.** A dashboard card with the real battery level, charging state and Low Power Mode from iOS. CleanSpace doesn't claim battery savings: iOS doesn't expose them, and freeing storage doesn't measurably change battery life.
- **Speed.** File sizes are stored in Caches keyed by modification date, like the photo fingerprints, so launches and rescans skip re-measuring unchanged items.
- **Glass.** Remaining solid surfaces use the glass surface, navigation bars use the system (Liquid Glass) bar, and popup glass is lighter.

### Final polish

- **Photo cards.** The Cleanup categories on the dashboard are cards that show your own first items: the first duplicate pair (the copy to keep is marked), the first look-alike pair, your newest screenshot, your largest video (with its length), a chat photo, and the avatars of the first duplicate contact. A pill shows the count and size, or what to do next ("Scan", "Allow access", "All clear"). Blurry Photos and Calendar Events stay as compact cards under More.
- **Quick Clean.** Tapping the water refills it from 0% over 2 seconds, then pre-selects the safe picks and opens Review. If Review is cancelled, exactly the items Quick Clean added are deselected again; anything chosen by hand stays.
- **Clear.** The selection bar on the dashboard and in every category has a Clear button.
- **Colors.** A calm sapphire blue matching the blue logo, muted category colors, and bright frosted cards in light mode (Liquid Glass in dark mode).
- **Launch.** First launch shows three explainer pages; later launches show a short animation where the logo resolves, draws and fills.
- **Popups.** One larger glass X on each popup (the drag handle can no longer swallow taps), no duplicate Done buttons.

### Teal theme, Liquid Glass, selection on request

- **Colors.** Fresh teal is the main color (actions, the water, selection) with indigo as its companion, on a calm neutral base with soft teal, indigo and pink washes (`AppBackdrop`). Each cleanup category has its own two-tone icon: indigo duplicates, violet similar photos, sky screenshots, green chat photos, rose videos, amber blurry photos, orange contacts, pink calendar. The app icon now runs mint to teal to indigo.
- **Liquid Glass.** On iOS 26 and later, cards, sections, the scan button, primary buttons and the floating selection bar use Apple's `glassEffect` (tinted and touch-responsive for buttons). Earlier versions fall back to frosted material. Building needs the iOS 26 SDK (Xcode 26 or later).
- **Selection.** Nothing is selected when a scan finishes or when a category opens. In Duplicate and Similar Photos, "Select suggested (N)" picks the recommended extras, and "Deselect all" clears them.
- **Recover** moved to Cleanup History (top card) and Settings (under History).
- **Launch.** A short animation (the mark springs in, then the name) replaces the blank first frame.

### Exact scan status, faster scans, Recover

- **Scan status bug.** Photo progress used to reach "N of N" when fingerprinting ended, while grouping, duplicate confirmation and size measuring were still running, so the scan looked finished early. `ScanPhase` now has an `analyzing` step, and `AppState.scanStatus` derives one status from the real phases: Scanning (with counts), Analyzing, Complete (only when every started scan has finished) or Didn't finish (if a scan stream ends without a result). The Scan button follows it: "Scanning…" with progress, "Analyzing…", and "Scan Again" only once complete.
- **Faster scans, genuinely.**
  - `FingerprintCache` stores each photo's fingerprint keyed by its modification date, so later scans skip thumbnails and analysis for unchanged photos. It lives in Caches and is removed by Clear temporary files.
  - The slow per-photo resource lookup for chat detection is skipped for photos that can't be chat photos.
  - Duplicate confirmation reads file contents only for candidates whose sizes match.
  Progress still counts every photo.
- **Recover deleted items.** A card in Cleanup explains that deleted photos and videos stay in Recently Deleted in Photos for 30 days, gives the steps, opens Photos, and shows thumbnails of what CleanSpace removed in the last 30 days with days left. iOS doesn't allow apps to restore from Recently Deleted, so recovery happens in Photos.

### Glass popups, real compression, visual history

- **Popups.** Every popup (category info, previews, review, permissions, settings pages, vault viewer, compression, swipe help) opens full screen, sliding up from the bottom, on a frosted glass material with a light tint for readability. A grab handle at the top drags down to dismiss; popups without their own Done button also get a close button. Flows that must not be interrupted (Review while deleting, compression) have no drag handle. System confirmation dialogs and alerts are drawn by iOS and keep the system style.
- **Video compression, rebuilt.** The old version used AVAssetExportSession presets, which choose their own bitrate, so the result couldn't follow a target size and 1080p sources often barely shrank. It now re-encodes with AVAssetReader and AVAssetWriter at an explicit bitrate computed from the chosen target (High about 60%, Balanced about 35%, Smallest about 20% of the original, with a floor for watchable quality), at a resolution that suits that bitrate. HEVC is used when available, H.264 otherwise; HDR is converted to standard range through a video composition; audio is stereo AAC. After encoding, the file is opened and checked to be playable and full length before it's saved. The screen shows original, target and compressed sizes, live progress, and lets you play the compressed copy. `CompressionEstimator` is unit-tested.
- **Cleanup History with thumbnails.** On the Review screen, before anything is deleted, CleanSpace captures a small JPEG of each item (up to 60 per cleanup) and keeps only those iOS confirmed as deleted. History shows them in a grid, with video lengths, "+N more" beyond the limit, and a detail view with date and size. Thumbnails stay on the device and are removed when history is cleared. Records from earlier versions show text only.
- **Scan completion.** Finishing a scan no longer selects anything, so the dashboard shows no "selected" badges and no Review bar until you choose. Suggested picks for Duplicate and Similar Photos are applied the first time you open that category (or when a scan finishes while it's open). Swipe mode starts with nothing selected and drops the suggestions.
- **Dashboard.** The segmented ring and rim sweep, which looked like a loading indicator, are gone. The water orb now rests in a still glass disc with a soft halo. Blues are softer and brighter, shadows lighter, and cards have a subtle glass edge. Scan Again is a compact pill (about 56 pt tall) with inline progress; Review Changes is a smaller capsule.

### Quieter design, exact scan status, faster scans, Recover

- **Design.** Decorative gradients, glows, large rounded cards and extra glass are gone. Content sits on flat surfaces with hairline borders and a 14 pt corner radius. Apple's Liquid Glass (`glassEffect`, iOS 26 and later) is used only for controls and floating bars, where Apple uses it: buttons, the floating Review Changes bar and popup close buttons. On iOS 17 to 25 they fall back to a solid tint or system material. Building needs the iOS 26 SDK (Xcode 26 or later). One button style (`CSButtonStyle`) is used throughout: compact capsules with 44 pt touch targets.
- **Dashboard.** Used space and a single capacity bar (used, can be freed, free), a scan status line with one fitting action, a suggested next step once there's something to free, and grouped Cleanup and Tools lists. The water orb and rings are no longer on the dashboard.
- **Scan status bug.** Photo progress used to reach "N of N" when fingerprinting ended, while grouping, duplicate confirmation and size measuring were still running, so the scan looked finished early. `ScanPhase` now has an `analyzing` step, and `AppState.scanStatus` derives one status from the real phases: Scanning (with counts), Analyzing, Complete (only when every started scan has finished) or Didn't finish (if a scan stream ends without a result). Scan Again appears only when complete; while working the action is Stop.
- **Faster scans, genuinely.**
  - `FingerprintCache` stores each photo's fingerprint keyed by its modification date, so later scans skip thumbnails and analysis for unchanged photos. It lives in Caches and is removed by Clear temporary files.
  - The slow per-photo resource lookup for chat detection is skipped for photos that can't be chat photos (with location, Live Photos, Portrait shots, bursts, screenshots).
  - Duplicate confirmation reads file contents only for candidates whose file sizes match.
  Progress still counts every photo. Nothing is faked.
- **Recover deleted items.** A row in Cleanup explains that deleted photos and videos stay in Recently Deleted in Photos for 30 days, gives the steps, opens Photos, and shows thumbnails of what CleanSpace removed in the last 30 days with days left. iOS doesn't allow apps to restore items from Recently Deleted, so recovery happens in Photos.
- **Popups.** More opaque glass, content that eases in after the slide-up, a redesigned category explainer, and calmer empty, scanning, vault and success screens.

## Requirements

- Xcode 16 or later (the project uses Xcode's folder-synchronized groups)
- iOS 17.0 or later, iPhone only, portrait
- Swift 5 language mode, SwiftUI, no third-party dependencies

## Build and run

1. Open `CleanSpace.xcodeproj`.
2. Select the **project** (not a target), open **Build Settings**, and change `CLEANSPACE_BASE_BUNDLE_ID` from `com.yourname.cleanspace` to something unique. The app, widget, tests and App Group IDs are all derived from it.
3. Select the **CleanSpace** target, open **Signing & Capabilities**, and choose your Team. Do the same for the **CleanSpaceWidget** target.
4. Connect an iPhone, enable **Developer Mode** (Settings › Privacy & Security), and select it as the run destination.
5. Press **Run** (⌘R). The first time, trust your developer certificate in Settings › General › VPN & Device Management.

**Signing with a free Apple ID.** If Xcode can't create the App Group (`group.<your bundle ID>`) for a free account, remove the **App Groups** capability from both targets. Everything still works; the widget then shows live storage but not "can free" or the last scan time.

**Adding the widget.** Touch and hold the Home Screen, tap Edit › Add Widget, and search for CleanSpace. Lock Screen sizes are under Customize on the Lock Screen.

The Simulator works too. Drag photos and videos into it, add contacts or events, and use Features › Face ID › Enrolled to try the vault.

To run the unit tests, press ⌘U (scheme **CleanSpace**, any iOS 17+ simulator).

`project.yml` can regenerate the project if needed: `brew install xcodegen && xcodegen generate`.

## Features

- **Dashboard.** Real capacity and free space from iOS (`URLResourceValues`), the water gauge, per-category estimates, Scan Now / Stop with progress, last scan time, total freed so far, a Tools row, and a floating bar for everything selected.
- **Similar and duplicate photos.** Groups of identical copies and near-identical shots (bursts, re-saves, edits). Each group shows a "Best" badge on the photo to keep, pre-selects the rest, never pre-selects favorites, and warns if every photo in a group is selected.
- **Screenshots.** Month-sectioned grid with sizes, Select All and per-month Select, and a preview.
- **Large videos.** Largest first, filterable to videos of 25 MB or more, with duration, date and resolution. Tap to play; touch and hold to compress instead.
- **Blurry photos (bonus).** Out-of-focus photos, never pre-selected.
- **Duplicate contacts.** "Likely duplicates" and "Worth a closer look", with **Merge** (choose the name and photo to keep) or **Delete** for specific cards. At least one card always stays.
- **Calendar cleanup.** Old events grouped by year with a cutoff menu, and duplicate events with the original marked as kept. Repeating events and read-only calendars are never touched.
- **Swipe mode.** Swipe left to mark, right to keep, or use the buttons. Tap a card to preview or play it. Undo steps back one card and restores the previous selection. Swiping only changes the selection; deleting still happens on the review screen.
- **Compress videos.** A tool screen ranks videos by how much they'd save. Compressing saves a new copy with the original's date, location and favorite flag, then offers to delete the original (iOS confirms).
- **Private vault.** Add photos and videos from the photo picker; CleanSpace encrypts them and offers to delete the originals. View, play, save back to Photos, or delete from the vault.
- **Widget.** Small and Medium Home Screen sizes with the water gauge, and circular and rectangular Lock Screen sizes. Refreshes every 30 minutes and whenever a scan or cleanup finishes.
- **One review screen.** Every category funnels into the same Review sheet, followed by the space-freed summary with honest reporting of anything that couldn't be removed.
- **Settings.** Working Access rows for Photos, Contacts and Calendar with status badges, a weekly scan reminder, Clear temporary files, vault options (Face ID, change passcode, erase), cleanup history, About, What's New, Privacy Policy, Terms of Use, Rate CleanSpace, and version and build. "Send Feedback" appears once you set `AppInfo.feedbackEmail`.
- **Light and dark mode**, Dynamic Type friendly layouts, Reduce Motion respected, VoiceOver labels and actions (including swipe-mode actions).

## Architecture

MVVM with Swift's Observation framework (`@Observable`), grouped by feature:

```
CleanSpace/          App target
  App/             CleanSpaceApp, RootView, AppState (app-wide state + navigation), Routes
  Dashboard/       DashboardView, storage hero card, scan button, category cards, tool tiles
  Onboarding/      First-launch welcome
  PhotoScanner/    SimilarPhotosModel, similar/blurry screens, group detail
  Swipe/           Swipe mode hub and card deck
  Screenshots/     MediaListModel (shared with videos), ScreenshotsView
  Videos/          LargeVideosView, row, player
  Compression/     VideoCompressor (estimator + export job), compression screens
  Contacts/        ContactsModel, duplicate list, merge/delete detail
  Calendar/        Calendar models, duplicate finder, CalendarModel, cleanup screen
  Vault/           Keychain + PBKDF2, AES-GCM file format, VaultStore actor, lock, screens
  Review/          CleanupPlan, CleanupViewModel, ReviewCleanupView, CleanupSummaryView
  Settings/        Settings, change passcode, cleanup history
  Permissions/     PermissionCenter, PermissionGate, pre-permission / denied / limited UI
  Services/        PhotoKit, Contacts, EventKit, thumbnails, scanners (no UI)
  Components/      Reusable views
  Shared/          Models and pure algorithms
CleanSpaceShared/    Compiled into both the app and the widget: design tokens, formatting,
                   storage reading, the water gauge and logo views, the App Group snapshot
CleanSpaceWidget/    WidgetKit extension
CleanSpaceTests/     Unit tests
Config/            Info.plists and entitlements
```

- **Views** are thin and read `AppState` from the environment.
- **Models** own scan state. Each scan carries a token, so a cancelled scan can never overwrite a newer one.
- **Services** do the work off the main thread. The vault's file work runs in an actor.
- **Pure logic** (`PerceptualHash`, `SimilarityGrouper`, `ContactDuplicateFinder`, `PhotoRanking`, `CalendarDuplicateFinder`, `CompressionEstimator`, `PBKDF2`, `VaultCrypto`) has no UI dependencies and is unit-tested.
- **Selection** is a single value type (`CleanupSelection`, now including calendar events). Nothing in it is acted on until the Review screen is confirmed.

## Permissions

| Access | Why | When it's asked |
|--------|-----|-----------------|
| Photos (read & write) | Find photos and videos to clean, delete what you approve, save compressed videos and vault exports | After an in-app explanation, when you tap Scan Now or open a photo feature |
| Contacts | Find and merge or delete duplicates | When you open Duplicate Contacts |
| Calendar (full access) | Find old and duplicate events and delete what you approve | When you open Calendar Events |
| Face ID | Unlock the vault, if you turn it on | When you choose to use Face ID for the vault |

- Scan Now asks only for Photos, so nobody faces three permission prompts in a row. Contacts and Calendar are asked for when you open them.
- Before each system prompt, CleanSpace explains exactly why it needs access.
- **Denied or restricted:** a clear message and an **Open Settings** button. The rest of the app keeps working. Calendar "write only" access counts as denied, because events can't be read with it.
- **Limited photo access:** a banner explains that results cover only shared photos, and **Manage** opens iOS's picker.
- Changes made in Settings are picked up when the app returns to the foreground.

## How detection works

**Similar and duplicate photos.**
- Each on-device photo is drawn into a grayscale buffer of at most 256 px, requested with iCloud downloads disabled. It is shrunk with an area filter to 9×8, and a 64-bit **difference hash** (dHash) is computed from adjacent-pixel brightness comparisons.
- Photos are processed in batches of 64, several at a time, with memory released per batch.
- Grouping avoids comparing every photo to every other:
  1. Identical hashes are bucketed in a dictionary.
  2. For near-duplicates anywhere in the library, the hash is split into 8 bands of 8 bits. Any two hashes within Hamming distance 7 must share at least one band exactly, so only photos that collide in a band are compared (threshold 5).
  3. For bursts, photos taken within 90 seconds of each other are compared with a looser threshold (12).
  4. An aspect-ratio guard keeps crops and rotations apart, and union-find merges the matches.
- A group is labelled **Duplicates** if all hashes and dimensions match, otherwise **Similar shots**.
- The keeper is chosen by: favorite → not a screenshot → higher resolution → noticeably sharper → newer → larger file.

**Blurry photos.** The variance of the Laplacian (a measure of edge detail) on the same small copy. Low-contrast scenes such as sky, fog and walls are excluded so they aren't mislabelled.

**Screenshots.** PhotoKit's `photoScreenshot` media subtype, newest first.

**Large videos.** All videos with their on-record byte size (summed over every resource of the asset), sorted by size. Sizes are read in the background and cached, and "large" means 25 MB or more.

**File sizes.** Sizes come from each `PHAssetResource`'s byte count (every resource of the asset: original, edits, Live Photo video) and are computed only for the photos that end up in results.

**Duplicate contacts.**
- Names are folded for case, accents and width, and compared order-insensitively ("Smith José" = "jose smith").
- Phone numbers are reduced to digits and compared on their last 10, so international and local formats match. Numbers shorter than 7 digits are ignored.
- Emails are trimmed and lowercased.
- Contacts are linked if they share a phone number or email, or have the same name when one card has no phone or email at all. The same name with *different* details is not linked, because those are often different people.
- A number or email shared by more than 6 cards (a switchboard) is ignored.
- Groups whose names are compatible (equal, or one contained in the other) are "Likely". The rest are "Worth a closer look".

**Merging** keeps the chosen card, adds the union of phones, emails, postal addresses, URLs, social profiles, messaging handles, relations and dates, fills empty fields (company, job title, birthday…), applies the chosen photo, and deletes the other cards, all in a single `CNSaveRequest`. The `note` field is never read, because it requires a special entitlement.

**Old calendar events.** Past, non-recurring events on calendars you can edit whose end is older than the chosen cutoff (6 months, 1 year, 2 years or 5 years). EventKit caps each query at four years, so the last 10 years (plus 2 ahead, for duplicates) are read in three-year windows and de-duplicated by identifier.

**Duplicate events.** Same title (ignoring case, accents and extra spaces), same start and end to the minute, and same all-day flag. Untitled events are never grouped. The one created first is kept; the later copies are suggested.

**Video compression.** Re-encodes with `AVAssetExportSession`: High is 1080p HEVC (falling back to H.264 if the device can't encode HEVC), Balanced is 720p, Small is 540p. The size shown before you start is an estimate from typical bitrates. A result that isn't at least 10% smaller is thrown away and you're told the video is already efficient.

## Private vault: how it's protected

- **Encryption.** Each item is encrypted with AES-256-GCM (Apple CryptoKit) in 1 MB chunks, so large videos never need to fit in memory. Every chunk authenticates its position, so chunks can't be reordered or dropped without detection. Thumbnails and the item index are encrypted the same way.
- **Key.** A random 256-bit key is created on first use and kept in the Keychain as "when unlocked, this device only". It never syncs to iCloud and isn't restored to another device.
- **Passcode.** Stored only as a salted PBKDF2-HMAC-SHA256 hash (60,000 rounds) in the Keychain and compared in constant time. After 5 wrong tries there's a 30-second wait that doubles with each further miss, up to 15 minutes, and survives restarting the app.
- **Face ID** is optional, needs a successful scan to turn on, and the passcode always works too.
- **Files** live in Application Support with iOS Complete file protection and are excluded from backups. Decrypted video is written to a protected temporary file only while it plays, and deleted afterwards.
- **Relocking.** The vault locks when you leave its screen or the app goes to the background, and its contents are hidden in the app switcher.
- **What it isn't.** The passcode gates access inside CleanSpace; the file key is protected by the iPhone's own security rather than derived from the passcode (that's what lets Face ID work). Deleting CleanSpace deletes the vault, and a forgotten passcode can only be fixed by erasing it. Both are stated before setup.

## Widget

The widget reads live storage itself. What CleanSpace can free, the last scan time and the lifetime total come from a small snapshot the app writes to the App Group after scans and cleanups (`SharedStore`). The App Group ID is `group.$(CLEANSPACE_BASE_BUNDLE_ID)`, passed to both targets through their Info.plists, so changing the bundle ID in one place is enough. If the App Group isn't available, the widget still shows storage.

## Deletion and safety

- Nothing is deleted outside the Review screen, with two explicit exceptions that each ask first: deleting a video's original after compressing it, and deleting originals after moving them into the vault.
- **Photos and videos** are deleted with `PHPhotoLibrary.performChanges`, so iOS shows its own confirmation too. If you decline, nothing is removed. Afterwards CleanSpace re-queries the library and reports only what was actually removed.
- **Contacts and calendar events** get an extra confirmation, because iOS doesn't show one and they can't be undone. Each event is deleted individually, then checked, so one read-only event can't block the rest.
- **Vault items** don't go to Recently Deleted, and the delete confirmation says so.
- Items that couldn't be deleted stay selected so you can try again.

## Privacy

- No network code, no analytics, no crash reporters, no ads, no accounts.
- Photos are analyzed from local thumbnails only, with iCloud downloads explicitly disabled. Compression also works only on videos already on the device.
- Scan results live in memory. `UserDefaults` holds the last scan date, the total freed, the cleanup history (dates, sizes and counts only), vault settings, and whether the welcome was shown. The optional weekly reminder is a local notification scheduled on the device. The App Group snapshot holds three numbers and a date.
- Privacy manifests (`PrivacyInfo.xcprivacy`) are included for the app and the widget.

## TestFlight

A TestFlight build has to be archived and uploaded from a Mac by someone with a paid Apple Developer Program membership, so it isn't included here. Everything needed is in the repo: [TESTFLIGHT.md](TESTFLIGHT.md) walks through it step by step, `scripts/testflight.sh` archives and uploads from the command line, and `.github/workflows/testflight.yml` does the same on GitHub's macOS runners.

## Limitations

- **Recently Deleted.** Deleted photos and videos stay there for 30 days, so free space may not rise until you empty it. The summary screen explains this and has an Open Photos button.
- **iCloud-only items** aren't analyzed, compressed or added to the vault, because CleanSpace never downloads your media.
- **File sizes** come from `PHAssetResource`'s `fileSize` value, which works but isn't a documented public property.
- **Compression estimates** are based on typical bitrates, so the real result can differ. Compressing needs free space for the new copy, and keeping the app open.
- **Calendar.** Repeating events, subscribed calendars, holidays and birthdays are never changed. Events from shared or invited calendars may refuse deletion; they're reported as not deleted.
- **Vault** contents can't be recovered after deleting the app or forgetting the passcode.
- **Widget** data other than storage depends on the App Group, which may need to be removed for free-account signing.
- **Detection limits.** The perceptual hash is tuned to avoid false matches, and the blur check is a heuristic, which is why blurry photos are never pre-selected.
- **Other apps' data.** iOS doesn't let any app clear other apps' caches.
- **Platforms.** iPhone only, as the brief requires.

## Testing

**Unit tests** (`CleanSpaceTests`, run with ⌘U):
- Perceptual hash stability, hash distance, blur and contrast measures.
- Grouping of exact duplicates, near-duplicates, bursts, the aspect-ratio guard and transitive merges.
- Contact normalization and matching rules.
- Best-photo ranking, month sectioning, and selection logic (including calendar events).
- Calendar duplicate rules and cutoffs.
- Vault encryption: round trips across chunk sizes, file and memory formats matching, wrong key, tampering, reordered chunks, bad headers.
- PBKDF2 against published SHA-256 test vectors, and constant-time comparison.
- Compression estimates.

**Manual checks on a device:**
- Grant, deny and limit each permission, then change it in Settings while the app is in the background.
- Decline iOS's delete confirmation and check nothing changes.
- Compress a video, check the copy's date and place in Photos, then delete the original.
- Set up the vault, add a photo and a video, background the app, and unlock with Face ID and with the passcode. Enter 5 wrong passcodes to see the wait.
- Delete old and duplicate events and check them in the Calendar app.
- Add the widget, run a scan, and check it updates.
- Swipe through a pile, undo, and review.

**Build status.** The sources and project were written and syntax-checked outside Xcode, since no Swift compiler was available where they were written. The project hasn't been compiled or run on a device yet. Build it once in Xcode before relying on it, and fix any compile errors that come up.
