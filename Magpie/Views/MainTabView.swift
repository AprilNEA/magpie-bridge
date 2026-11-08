import SwiftUI

struct MainTabView: View {
    let session: Session
    @State private var pane = Pane.overview

    private enum Pane: Hashable {
        case overview, requests, setup, settings
    }

    var body: some View {
        TabView(selection: $pane) {
            Tab("概览", systemImage: "gauge.with.dots.needle.33percent", value: Pane.overview) {
                NavigationStack { OverviewView(session: session) }
            }
            Tab("请求", systemImage: "list.bullet.rectangle", value: Pane.requests) {
                NavigationStack { RequestsView(session: session) }
            }
            Tab("配置", systemImage: "terminal", value: Pane.setup) {
                NavigationStack { SetupView(session: session) }
            }
            Tab("设置", systemImage: "gearshape", value: Pane.settings) {
                NavigationStack { SettingsView(session: session) }
            }
        }
        .task {
            if session.info == nil {
                await session.refresh()
            }
        }
    }
}
