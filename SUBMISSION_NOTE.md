CleanSpace: iPhone storage cleaner (Swift, SwiftUI, iOS 17+, PhotoKit, Contacts, EventKit, WidgetKit). Everything runs on-device, with no network or accounts.

Tools: Xcode, Swift 5, XCTest, CryptoKit, no third-party libraries. Built with help from Claude (Anthropic).

Works: storage dashboard with water gauge and Quick Clean; duplicate, similar, chat and blurry photos; screenshots; large videos with real compression; duplicate contacts with merge; calendar cleanup; one shared Review screen with space-freed summary and history; encrypted PIN/Face ID vault; widget; light/dark mode.

Missing: an uploaded TestFlight build (needs a paid account); the script, CI workflow and guide are included.

Hardest problem: scanning large libraries quickly and honestly. Perceptual-hash bands limit comparisons, content hashes confirm exact duplicates, and cached fingerprints make rescans fast.
