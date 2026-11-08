import SwiftUI

@main
struct MagpieApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            MagpieRootView(session: session)
        }
    }
}

private struct MagpieRootView: View {
    let session: Session

    var body: some View {
        if session.credential == nil {
            SignInView(session: session)
        } else {
            MainTabView(session: session)
        }
    }
}
