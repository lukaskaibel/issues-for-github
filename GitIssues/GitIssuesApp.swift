import GitIssuesKit
import SwiftUI

@main
struct GitIssuesApp: App {
    // Sets up notifications before one that launched the app is handed over.
    #if os(macOS)
    @NSApplicationDelegateAdaptor(GitIssuesAppDelegate.self) private var delegate
    #else
    @UIApplicationDelegateAdaptor(GitIssuesAppDelegate.self) private var delegate
    #endif

    var body: some Scene {
        GitIssuesScene()
    }
}
