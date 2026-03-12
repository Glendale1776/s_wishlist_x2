import SwiftUI

@main
struct s_wishlist_x2App: App {
    @StateObject private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authStore)
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
        }
    }
}
