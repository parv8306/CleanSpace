import SwiftUI

@main
struct CleanSpaceApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.Palette.brand)
        }
    }
}
