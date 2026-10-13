import SwiftUI
import GoogleSignIn

@main struct SoloPocketApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var account = GoogleAccount()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(account)
                .tint(Color(red: 0.09, green: 0.40, blue: 0.32))
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .onChange(of: phase) { _, phase in if phase == .background { model.pause() } }
        }
    }
}
