import SwiftUI

@main
struct BrewwwwApp: App {
    @StateObject private var store = BrewStore()
    @AppStorage("autoTheme") private var autoTheme = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(autoTheme ? nil : .dark)
        }
    }
}
