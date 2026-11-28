import SwiftUI

@main
struct LocalStudioApp: App {
    @State private var session = ChatSession()

    var body: some Scene {
        WindowGroup {
            ChatView(session: session)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}

enum StudioPalette {
    static let fullscreenComposer = Color(white: 30 / 255)
    static let accent = Color(red: 51 / 255, green: 96 / 255, blue: 243 / 255)
    static let bubble = Color(red: 2 / 255, green: 5 / 255, blue: 93 / 255)
    static let prompt = Color(red: 222 / 255, green: 225 / 255, blue: 255 / 255)
}
