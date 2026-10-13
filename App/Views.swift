import SwiftUI
import SoloCore
import GoogleSignInSwift
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var account: GoogleAccount
    var body: some View {
        TabView(selection: $model.tab) {
            DeviceView().tabItem { Label("Solo", systemImage: "wifi") }.tag(0)
            LibraryView().tabItem { Label("本地批次", systemImage: "tray.full") }.tag(1)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.busy {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(model.status).font(.subheadline); Spacer(); Button("暂停") { model.pause() } }
                    ProgressView(value: model.progress)
                    Text("请保持 App 在前台；切到后台会暂停，文件会保留。 ").font(.caption).foregroundStyle(.secondary)
                }.padding().background(.regularMaterial)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil || account.message != nil }, set: { if !$0 { model.error = nil; account.message = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil; account.message = nil }
        } message: { Text(model.error ?? account.message ?? "") }
    }
}

struct DeviceView: View {
    @EnvironmentObject var model: AppModel
    @State private var showBatch = false
    private var days: [String] { Set(model.visibleSessions.map(\.dateLabel)).sorted(by: >) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.demo ? "演示列表" : "连接 Solo", systemImage: "stopwatch").font(.title2.bold())
                        Text(model.status).font(.subheadline).foregroundStyle(.secondary)
                        if model.sessions.isEmpty {
                            Text("在 iPhone 设置中连接你的 Solo 显示的 Wi-Fi，\n然后返回这里读取列表。设备可以使用任意名称。")
                                .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Button { model.scan() } label: { Label("读取 session 列表", systemImage: "arrow.clockwise") }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.demo)
                        Text("点击读取即可自动连接；首次出现本地网络弹窗时，请点允许。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let message = model.lastConnectionError {
                            Text(message).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                        }
                        if let log = model.diagnosticURL {
                            ShareLink("导出最近连接日志", item: log).disabled(model.busy)
                        }
                    }.padding(.vertical, 8)
                } footer: { Text("时间按设备记录显示。圈数与最快圈来自 Solo，包含未验证的圈段。") }
                Section {
                    Toggle("隐藏没有最快圈的 session", isOn: $model.hideSessionsWithoutBestLap)
                        .disabled(model.busy).accessibilityIdentifier("hideSessionsWithoutBestLap")
                    if !model.sessions.isEmpty {
                        Text("显示 \(model.visibleSessions.count) / \(model.sessions.count) 条记录")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } footer: { Text("仅筛选显示，不删除设备记录。没有最快圈也可能是未完成有效计时圈。") }
                ForEach(days, id: \.self) { day in
                    Section(day) {
                        ForEach(model.visibleSessions.filter { $0.dateLabel == day }) { session in
                            Button {
                                if !model.selected.insert(session.id).inserted { model.selected.remove(session.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: model.selected.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).padding(.top, 2)
                                    SessionRow(session: session, downloaded: model.localSessionKeys.contains(AppModel.key(session)))
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.busy)
                                .accessibilityIdentifier("session_" + session.filename)
                                .accessibilityLabel("\(session.title)，\(session.laps) 圈，最快 \(session.bestLabel)")
                                .accessibilityValue(model.selected.contains(session.id) ? "已选择" : "未选择")
                        }
                    }
                }
                if model.sessions.isEmpty {
                    ContentUnavailableView("还没有 session 列表", systemImage: "wifi", description: Text("连好 Solo Wi-Fi 后点击读取。下载过程无需互联网。"))
                } else if model.visibleSessions.isEmpty {
                    ContentUnavailableView("没有带最快圈的记录", systemImage: "line.3.horizontal.decrease.circle", description: Text("关闭上方筛选即可查看全部 session。"))
                }
            }
            .navigationTitle("从 Solo 下载")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !model.visibleSessions.isEmpty {
                        Button(model.selected.count == model.visibleSessions.count ? "取消全选" : "全选") {
                            model.selected = model.selected.count == model.visibleSessions.count ? [] : Set(model.visibleSessions.map(\.id))
                        }.disabled(model.busy)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.visibleSessions.isEmpty {
                    Button { showBatch = true } label: {
                        Text(model.selected.isEmpty ? "选择要下载的 session" : "下载所选 \(model.selected.count) 个 session")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(model.selected.isEmpty || model.busy)
                        .accessibilityIdentifier("prepareBatch").padding().background(.regularMaterial)
                }
            }
            .sheet(isPresented: $showBatch) { BatchForm(sessions: model.selectedSessions) }
        }
    }
}

struct SessionRow: View {
    let session: Session
    var downloaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(session.title).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if downloaded { Label("已存手机", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            Text(session.track.isEmpty ? "未命名赛道" : session.track).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 22) {
                metric("设备圈数", "\(session.laps)")
                metric("设备最快圈", session.bestLabel)
                metric("时长", session.durationLabel)
            }
            Text(session.sizeLabel).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).monospacedDigit() }
    }
}

struct BatchForm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let sessions: [Session]
    @State private var metadata = BatchMetadata()
    @State private var folderPreview = ""
    @State private var folderPreviewError: String?
    private var filePreviews: [String] { BatchStore.fileNames(metadata: metadata, sessions: sessions) }
    private var missingMetadata: Bool {
        [metadata.title, metadata.driver, metadata.vehicle].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(sessions.count) 个 session · " + ByteCountFormatter.string(fromByteCount: Int64(sessions.reduce(0) { $0 + $1.size }), countStyle: .file)).font(.headline)
                    Text("下面的信息应用于这一整批。文件夹按记录日期、车手、车型命名；同名批次会加序号。上传 Google Drive 完全可选。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("标注这一批") {
                    TextField("批次名称", text: $metadata.title).accessibilityIdentifier("batchTitle")
                    TextField("车手姓名（用于文件夹名）", text: $metadata.driver)
                    TextField("车型（用于文件夹名）", text: $metadata.vehicle)
                    TextField("备注", text: $metadata.notes, axis: .vertical).lineLimit(3...6)
                }
                Section("保存到") {
                    Label(model.downloadRootLabel, systemImage: "folder")
                    if let message = folderPreviewError {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    } else {
                        LabeledContent("本批文件夹", value: folderPreview.isEmpty ? BatchStore.folderBaseName(metadata: metadata, sessions: sessions) : folderPreview)
                            .textSelection(.enabled)
                    }
                    Text("在这个父文件夹内新建本批子文件夹；可到「设置 → 本地下载目录」更改。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("已选记录") {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title)
                            Text("\(s.laps) 圈 · 最快 \(s.bestLabel) · \(s.durationLabel)").font(.caption).foregroundStyle(.secondary)
                            Text(filePreviews[index]).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                Section {
                    Button(model.demo ? "演示模式，不进行下载" : "开始下载到手机") { model.startDownload(metadata); dismiss() }
                        .disabled(missingMetadata || folderPreviewError != nil || model.demo)
                        .accessibilityIdentifier("confirmDownload")
                }
            }.navigationTitle("新建下载批次").navigationBarTitleDisplayMode(.inline)
                .task(id: metadata) {
                    do {
                        let name = try await model.store.suggestedFolderName(metadata: metadata, sessions: sessions)
                        guard !Task.isCancelled else { return }
                        folderPreview = name; folderPreviewError = nil
                    } catch {
                        guard !Task.isCancelled else { return }
                        folderPreviewError = error.localizedDescription
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .onAppear {
                    if metadata.title.isEmpty {
                        let s = sessions.first
                        metadata.title = [s?.dateLabel ?? "", s?.track ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
                        metadata.driver = UserDefaults.standard.string(forKey: "lastDriver") ?? ""
                        metadata.vehicle = UserDefaults.standard.string(forKey: "lastVehicle") ?? ""
                    }
                }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                if model.batches.isEmpty { ContentUnavailableView("下载的记录保存在这里", systemImage: "tray", description: Text("从 Solo 下载后，每批信息和原始文件会一起保留。联网后再选择上传。")) }
                ForEach(model.batches) { batch in
                    NavigationLink { BatchDetail(batchID: batch.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(batch.metadata.title).font(.headline)
                            Text([batch.metadata.driver, batch.metadata.vehicle].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Label("\(batch.completedCount)/\(batch.files.count) 已存手机", systemImage: "iphone")
                                Spacer()
                                Text(batch.uploadedAt == nil ? "仅保存在手机" : "已备份 Drive").foregroundStyle(batch.uploadedAt == nil ? .secondary : Color.green)
                            }.font(.caption)
                            Text(batch.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }.navigationTitle("本地批次").refreshable { await model.reload() }
        }
    }
}

struct BatchDetail: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var account: GoogleAccount
    let batchID: UUID
    @State private var folder: URL?
    var batch: Batch? { model.batches.first { $0.id == batchID } }
    var body: some View {
        List {
            if let batch {
                Section("整批信息") {
                    LabeledContent("名称", value: batch.metadata.title)
                    LabeledContent("车手", value: batch.metadata.driver.isEmpty ? "未填写" : batch.metadata.driver)
                    LabeledContent("车型", value: batch.metadata.vehicle.isEmpty ? "未填写" : batch.metadata.vehicle)
                    if !batch.metadata.notes.isEmpty { Text(batch.metadata.notes) }
                }
                Section {
                    Label(batch.folderName, systemImage: "folder")
                        .font(.subheadline).textSelection(.enabled)
                    Text(folder.map { AppModel.folderLabel($0.deletingLastPathComponent()) } ?? "正在读取原保存位置…")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("本地文件夹") }
                footer: { Text("同一批原始文件和标注都保存在这个文件夹。选择上传 Google Drive 时，也会使用相同的文件夹名称。") }
                Section {
                    if !batch.downloadComplete { Button("继续下载未完成的 session") { model.resume(batch) }.disabled(model.busy) }
                    if batch.downloadComplete {
                        Button(batch.uploadedAt == nil ? "上传这一批到 Google Drive" : "已上传到 Google Drive", systemImage: "icloud.and.arrow.up") { model.upload(batch, account: account) }
                            .disabled(model.busy || batch.uploadedAt != nil)
                    }
                    if let id = batch.driveFolderID, batch.uploadedAt != nil, let url = URL(string: "https://drive.google.com/drive/folders/" + id) {
                        Link("查看 Google Drive 文件夹", destination: url)
                    }
                } header: { Text("\(batch.completedCount)/\(batch.files.count) 已存手机") }
                footer: { Text("上传需先恢复可上网的连接。成功上传后，手机上的原始文件会继续保留。") }
                Section("Session") {
                    ForEach(batch.files) { file in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(file.session.dateLabel).font(.caption).foregroundStyle(.secondary)
                            SessionRow(session: file.session, downloaded: file.downloaded)
                            if let error = file.error { Text(error).font(.caption).foregroundStyle(.orange) }
                            if file.downloaded, let folder {
                                ShareLink(item: folder.appendingPathComponent(file.filename)) { Label("导出原始文件", systemImage: "square.and.arrow.up").font(.caption) }
                            }
                            Text(file.filename).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                if let folder {
                    Section("批次说明") {
                        ShareLink("导出批次信息", item: folder.appendingPathComponent("batch.json"))
                        ShareLink("导出 session 表格", item: folder.appendingPathComponent("sessions.csv"))
                    }
                }
            }
        }.navigationTitle("批次详情").navigationBarTitleDisplayMode(.inline)
            .task {
                if let batch {
                    do { folder = try await model.store.folder(batch) }
                    catch { model.error = error.localizedDescription }
                }
            }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var account: GoogleAccount
    @State private var rootName = "Solo Sessions"
    @State private var choosingLocalRoot = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("父文件夹", value: model.downloadRootLabel)
                    Button("选择本地父文件夹", systemImage: "folder") { choosingLocalRoot = true }
                    if !model.usesDefaultDownloadRoot {
                        Button("恢复默认目录") { model.changeDownloadRoot(nil) }
                    }
                } header: { Text("本地下载目录") }
                footer: { Text("请在「文件 → 我的 iPhone」中选择文件夹。每批会在其中建立命名子文件夹。更改只影响新批次，已有批次保留在原位置。") }
                Section {
                    if !account.configured {
                        Label("Google Drive 尚未配置", systemImage: "wrench.and.screwdriver")
                        Text("本地下载可以正常使用。完成此 App 的 Google 连接设置后，即可在这里登录并选择上传文件夹。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if account.email.isEmpty {
                        GoogleSignInButton { Task { await account.signIn() } }.disabled(account.working)
                    } else {
                        LabeledContent("账号", value: account.email)
                        LabeledContent("上传主目录", value: account.folderName.isEmpty ? "尚未选择" : account.folderName)
                        Button("读取可用文件夹") { Task { do { try await account.refreshFolders() } catch { account.message = error.localizedDescription } } }
                        ForEach(account.folders, id: \.id) { folder in
                            Button { account.selectFolder(folder) } label: {
                                HStack { Label(folder.name ?? "文件夹", systemImage: "folder"); Spacer(); if folder.id == account.folderID { Image(systemName: "checkmark") } }
                            }
                        }
                        TextField("新建上传主目录名称", text: $rootName)
                        Button("在 Drive 创建并选用此目录") { Task { await account.createFolder(rootName) } }.disabled(account.working || rootName.isEmpty)
                        Button("退出此 Google 账号", role: .destructive) { account.signOut() }
                    }
                } header: { Text("Google Drive · 可选备份") }
                footer: { Text("同一批文件上传到同一个子文件夹。这里列出本 App 已获授权的文件夹；可先创建专用目录。只有你点击上传，文件才会发往 Google Drive。") }
                Section("连接 Solo") {
                    LabeledContent("连接目标", value: "当前 Wi-Fi 上的 Solo")
                    Text("连接设备屏幕显示的 Wi-Fi。不限制设备名称或序列号，无需将设备改名。")
                        .font(.footnote)
                    Text("连接 Solo Wi-Fi 后关闭 LocalDevVPN。在「设置 → 隐私与安全性 → 本地网络」中允许 Solo Pocket；Cellular Data 是另外的蜂窝数据开关。下载时保持 App 在前台。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("打开 App 系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    Button("检查本地网络连接") { model.checkLocalConnection() }.disabled(model.demo)
                    if let log = model.diagnosticURL { ShareLink("导出最近连接日志", item: log) }
                    Text("连接日志仅存在「文件 → 我的 iPhone → Solo Pocket → Solo Diagnostics」，包含连接步骤和网络错误，不包含原始遥测或 Google 登录信息。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于本地文件") {
                    Text("原始 XRZ/XRK 和整批标注保存在你选择的本地父文件夹。默认位置为「文件 → 我的 iPhone → Solo Pocket → Solo Sessions」。新批次按记录日期、车手、车型命名；同名时加序号。已有批次保留原文件夹名。")
                    Text("手机检查传输完整性。详细遥测分析仍可用 Mac 上的 libxrk 读取原始文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知")
                }
            }.navigationTitle("设置").disabled(model.busy)
                .fileImporter(isPresented: $choosingLocalRoot, allowedContentTypes: [.folder]) { result in
                    do { model.changeDownloadRoot(try result.get()) }
                    catch { if (error as NSError).code != NSUserCancelledError { model.error = error.localizedDescription } }
                }
        }
    }
}
