import SwiftUI

@main
struct TomaApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
