import SwiftUI

@main
struct TokenUsageWidgetApp: App {
    var body: some Scene {
        MenuBarExtra("Token Usage", systemImage: "bolt.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello (Token Usage)")
                .padding()
        }
        .frame(width: 300, height: 200)
    }
}
