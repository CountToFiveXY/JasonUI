import SwiftUI

@main
struct JasonUIApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("JasonApp") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 980, height: 700)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 460)
                .padding()
        }
    }
}
