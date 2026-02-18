import SwiftUI

@main
struct spackleApp: App {
    @StateObject private var ctl = AppController()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
