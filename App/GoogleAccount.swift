import SwiftUI
import GoogleSignIn
import SoloCore

@MainActor final class GoogleAccount: ObservableObject {
    @Published var email = ""
    @Published var folderID = ""
    @Published var folderName = ""
    @Published var folders: [DriveFile] = []
    @Published var message: String?
    @Published var working = false
    private(set) var accountID = ""
    let scope = "https://www.googleapis.com/auth/drive.file"
    var configured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return id.hasSuffix(".apps.googleusercontent.com")
    }
    init() {
        guard configured else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            Task { @MainActor in self?.apply(user) }
        }
    }
    private func apply(_ user: GIDGoogleUser?) {
        accountID = user?.userID ?? ""; email = user?.profile?.email ?? ""
        folderID = UserDefaults.standard.string(forKey: "driveFolderID." + accountID) ?? ""
        folderName = UserDefaults.standard.string(forKey: "driveFolderName." + accountID) ?? ""
    }
    func selectFolder(_ folder: DriveFile) {
        folderID = folder.id; folderName = folder.name ?? "Solo Sessions"
        UserDefaults.standard.set(folderID, forKey: "driveFolderID." + accountID)
        UserDefaults.standard.set(folderName, forKey: "driveFolderName." + accountID)
    }
    private var presenter: UIViewController? {
        var view = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = view?.presentedViewController { view = next }
        return view
    }
    func signIn() async {
        guard configured else { message = "Google Drive 连接尚未配置。本地下载可正常使用。"; return }
        guard let presenter else { return }
        working = true; defer { working = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [scope])
            guard result.user.grantedScopes?.contains(scope) == true else { throw SoloError.invalid("需要允许此 App 保存文件到 Google Drive") }
            apply(result.user); try await refreshFolders()
        } catch { message = error.localizedDescription }
    }
    func token() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser, user.grantedScopes?.contains(scope) == true else { throw SoloError.invalid("请先在设置中登录 Google Drive 并授权") }
        return try await user.refreshTokensIfNeeded().accessToken.tokenString
    }
    func client() -> DriveClient { DriveClient(token: { [weak self] in guard let self else { throw CancellationError() }; return try await self.token() }) }
    func refreshFolders() async throws { folders = try await client().folders() }
    func createFolder(_ name: String) async {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        working = true; defer { working = false }
        do {
            let drive = client(), key = "pendingDriveRoot." + accountID
            let id: String
            if let pending = UserDefaults.standard.string(forKey: key) { id = pending }
            else { id = try await drive.generateID(); UserDefaults.standard.set(id, forKey: key) }
            try await drive.ensureFolder(id: id, name: title, parent: nil)
            try await refreshFolders()
            if let folder = folders.first(where: { $0.id == id }) { selectFolder(folder) }
            UserDefaults.standard.removeObject(forKey: key)
        } catch { message = error.localizedDescription }
    }
    func signOut() { GIDSignIn.sharedInstance.signOut(); apply(nil); folders = [] }
}
