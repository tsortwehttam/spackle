import SwiftUI

@main
struct spackleApp: App {
    @StateObject private var ctl = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(ctl: ctl)
        } label: {
            if ctl.state == .awaiting || ctl.state == .replacing {
                Image(systemName: "ellipsis.circle.fill")
                    .renderingMode(.template)
            } else {
                Image("MenuBarIcon")
                    .renderingMode(.template)
            }
        }
    }
}
