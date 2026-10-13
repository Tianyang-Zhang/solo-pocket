# Solo Pocket

用 iPhone 从 AiM Solo 2 读取 session、批量下载，并保存到系统「文件」App。

[中文安装指南](#中文安装指南) · [English guide](#english-guide) · [下载 0.1.5 IPA](https://github.com/Tianyang-Zhang/solo-pocket/releases/download/v0.1.5/SoloPocket-0.1.5.ipa) · [中文 PDF](docs/installation-zh-CN.pdf)

## 中文安装指南

### 当前版本与适用范围

**0.1.5 已取消设备名称绑定。** 连接你的 Solo Wi-Fi 即可读取，不需要改设备名或登记序列号。此前 0.1.4 已在作者的 iPhone 和 Solo 2 上实测；0.1.5 的自动化测试和安装包检查见版本说明。

- 原生 iPhone App，最低 iOS 17；界面目前为中文。
- 适用于使用兼容 Wi-Fi 下载协议的 Solo。通过手机系统选择设备的 Wi-Fi，程序访问其默认接入点地址 `10.0.0.1`。任意设备名均可，包括中文名称。
- 实机基线为 Solo 2、固件 02.44.26。Solo 2 DL 等其它型号/固件可尝试同一连接流程，但尚未逐一实测；仅有 USB 连接的设备不在此 Wi-Fi 流程范围内。
- 个人自用可通过 **AltStore Classic + Remote AltServer + LocalDevVPN** 安装，不需要付费 Apple Developer 会员。
- Google Drive 是可选上传功能。当前安装包没有配置 Google OAuth，本地下载和文件管理可直接使用。
- 本项目是非官方个人工具，与 AiM 没有关联。

### 可以做什么

- 列表显示日期、时间、圈数、最快圈、时长和文件大小。
- 默认隐藏没有最快圈的记录；可关闭筛选查看全部，设备原数据不删除。
- 多选 session，整批填写一次批次名称、车手、车型和备注。
- 先下载到手机，支持选择本地父文件夹；每批保存在一个独立子目录。
- 文件夹使用「记录日期 + 车手 + 车型」，数据文件使用「车手 + 记录日期 + 时间」，保留原扩展名和文件内容。同名时增加序号。
- 下载中断后保留已完成文件，可继续剩余记录；保持 App 在前台下载。

当前不支持 HRZ 下载，也没有内置完整遥测分析。设备提供的圈数和最快圈不代表已经验证每圈路线完整。

### 1. 准备

准备 Mac、iPhone、可传数据的 USB 线，以及自己的 Apple 账号。首次配置让电脑和手机连接普通联网 Wi-Fi。

下载 [SoloPocket-0.1.5.ipa](https://github.com/Tianyang-Zhang/solo-pocket/releases/download/v0.1.5/SoloPocket-0.1.5.ipa)。如果 AltStore 和 Remote AltServer 已经配置好，直接跳到第 4 步。Release 中同时提供 `SHA256SUMS`；请选择 `.ipa` 安装包，不要下载源码 ZIP 当安装包。

### 2. 用 Mac 安装 AltStore Classic

1. 从 [AltStore 官方 macOS 安装页](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos)下载 AltServer，放入 Mac 的「应用程序」并打开。入口位于顶部菜单栏。
2. 用 USB 连接并解锁 iPhone；出现「信任此电脑」时点「信任」。
3. 在 Finder 中选择 iPhone，在「通用」里勾选「接入 Wi-Fi 时显示此 iPhone」，点「应用」。
4. 点击 AltServer 菜单栏图标，选择 **Install AltStore → 你的 iPhone**，按提示输入自己的 Apple 账号并完成验证。
5. 手机进入 **设置 → 通用 → VPN 与设备管理**，找到自己的开发者账号，点「信任」并完成确认。
6. 进入 **设置 → 隐私与安全性 → 开发者模式**，启用并按系统提示重启、确认，再打开 AltStore。

### 3. 配置 Remote AltServer 和 LocalDevVPN

使用支持 Remote AltServer 的 AltStore Classic 2.3 或更新版本，并更新电脑上的 AltServer。

1. 保持 iPhone 连接 Mac，AltServer 运行。
2. 手机打开 **AltStore → Settings → Remote AltServer → Set up Remote AltServer…**。
3. 按向导完成电脑配对，通过向导入口安装 **LocalDevVPN**。
4. 打开 LocalDevVPN，允许添加 VPN 配置并连接。
5. 回到 AltStore 完成设置；需要选择服务时，在 **Choose Server** 里选可用服务器。
6. 手机连接普通联网 Wi-Fi，保持 LocalDevVPN 开启，尝试 **My Apps → Refresh All**。

配置成功后，正常安装和刷新不需要自己的 Mac 在线。远程服务不可用时可稍后重试或换服务；配置完成却仍连接不上时，可按官方建议重启手机。[官方 Remote AltServer 指南](https://faq.altstore.io/altstore-classic/remote-altservers)

### 4. 安装或更新 Solo Pocket

1. 把下载的 `SoloPocket-0.1.5.ipa` 保存到 iPhone「文件」。可在手机上直接下载，或由 Mac 通过 AirDrop 传送。**保留 `.ipa` 后缀，不解压。**
2. 保持普通联网 Wi-Fi 和 LocalDevVPN 连接。
3. 打开 **AltStore → My Apps → 左上角 +**，选择 IPA。
4. 按提示使用安装 AltStore 时的同一个 Apple 账号，等待签名和安装完成，再打开 Solo Pocket。

以后更新也通过加号导入新版 IPA，沿用原账号覆盖安装。**不要先删除 Solo Pocket**，以免删除尚未备份的 App 本地文件。

### 5. 设置保存位置

在 **Solo Pocket → 设置 → 本地下载目录 → 选择本地父文件夹**中，选择「我的 iPhone」下的可写文件夹作为根目录。

默认位置为 **文件 → 我的 iPhone → Solo Pocket → Solo Sessions**。修改根目录只影响新批次，旧批次保留原位置。

```text
Solo Sessions/
  2026-10-11_Tom_KTM_390_Duke/
    Tom_2026-10-11_16-55-28.xrz
    Tom_2026-10-11_16-40-00.xrz
    batch.json
    sessions.csv
```

以上是命名示例。日期和时间来自 session 记录，非下载时间；跨日批次使用起止日期。同名时添加 `_2`、`_3` 等序号。批次名称和备注保存在元数据中。

### 6. 连接 Solo 并下载

1. **关闭 LocalDevVPN**。如果 Mac 上 AimMac 正在连接 Solo，先退出 AimMac。
2. 打开 Solo，在手机 **设置 → Wi-Fi** 中连接设备显示的 AiM Wi-Fi。这个网络没有互联网是正常的。
3. 回到 **Solo Pocket → Solo → 读取 session 列表**。出现「允许访问本地网络」时点「允许」。程序会自动检查连接，无需先点诊断按钮。
4. 多选 session →「下载所选」，整批填写批次名称、车手、车型及可选备注，核对文件夹和文件名预览后下载。
5. 下载期间保持 App 在前台；进入后台会暂停，可回到 App 继续。
6. 完成后在「本地批次」或系统「文件」中查看。

Google Drive 无需配置即可完成以上步骤。当前包显示 Google Drive 尚未配置是正常的；如需启用，需要配置自己的 Google OAuth 并重新构建，见[开发说明](docs/DEVELOPMENT.md)。

### 7. 保持 App 可用

免费签名有效期为 **7 天**。到期前连接普通联网 Wi-Fi，打开 LocalDevVPN，然后点 **AltStore → My Apps → Refresh All**，确认 AltStore 和 Solo Pocket 的剩余天数均已更新。后台刷新会尝试自动完成，但去赛道前建议手动确认一次。[AltStore 有效期说明](https://faq.altstore.io/altstore-classic/your-altstore)

| 操作 | 手机网络 | LocalDevVPN |
| --- | --- | --- |
| 远程安装、更新、刷新签名 | 普通联网 Wi-Fi | 开启 |
| 从 Solo 读取、下载 | Solo Wi-Fi | 关闭 |
| 查看已下载文件 | 不要求联网 | 不需要 |

如果 AltStore 自身过期而打不开，用 Mac 上的 AltServer 和原 Apple 账号重新安装 AltStore，再恢复刷新。保留 Solo Pocket 和本地数据。

### 常见问题

- **app in invalid format**：重新下载本页 Release 中的 IPA，确认没有选择源码 ZIP 或解压后的文件夹。
- **-80045**：错误码本身不足以判断原因。保留完整报错，可先用 Mac 本地 AltServer 路径重试；不要把删除 App 当作第一步。
- **读取列表超时**：确认 Solo Wi-Fi、VPN 已关闭、AimMac 未占用连接，并检查 **设置 → 隐私与安全性 → 本地网络 → Solo Pocket**。Cellular Data 不是本地网络权限。仍失败时在 App 中「导出最近连接日志」。
- **其它 Solo 设备无法连接**：0.1.5 不再检查设备名字。请使用设备的 Wi-Fi 接入点模式；如果仍提示握手或数据格式不兼容，导出日志以确认该型号/固件的协议差异。

### 源码与发布说明

构建、测试和可选 Google Drive 配置见[开发说明](docs/DEVELOPMENT.md)。公开仓库使用虚构演示 CSV，不包含个人下载记录或连接日志。0.1.5 是从本仓库重新构建的版本，保留协议握手、文件长度与校验和检查；测试结果和验证范围见[版本说明](docs/RELEASE-0.1.5.md)。

---

## English guide

### Current release and compatibility

**0.1.5 removes the device-name restriction.** Join your Solo Wi-Fi and read sessions without renaming the device or registering its serial number. Version 0.1.4 was physically tested with the author's iPhone and Solo 2; see the release notes for 0.1.5 automated tests and package validation.

- Native iPhone app, requiring iOS 17 or later. The app interface is currently in Chinese.
- Intended for Solo devices using a compatible Wi-Fi download protocol. Choose the device network in iPhone Settings; the app connects to its default access-point address, `10.0.0.1`. Any custom device name is accepted, including non-Latin names.
- Physical validation is based on a Solo 2 with firmware 02.44.26. Other models/firmware, including Solo 2 DL, can attempt the same connection flow but have not been individually tested. USB-only devices are outside this Wi-Fi workflow.
- Personal installation uses **AltStore Classic + Remote AltServer + LocalDevVPN** with a free Apple account. A paid Apple Developer membership is not required.
- Google Drive upload is optional. The distributed app has no Google OAuth configuration; local downloads and file management work without it.
- This is an unofficial personal project, not affiliated with AiM.

### Features

- Session list with date, time, lap count, best lap, duration and file size.
- Sessions without a best lap are hidden by default. Turn the filter off to show all; device records are not deleted.
- Select multiple sessions and enter one shared batch title, driver, vehicle and notes.
- Download to the phone first, with a configurable local parent folder and one subfolder per batch.
- Folder names use recording date + driver + vehicle. Data filenames use driver + recording date + time, preserving the original extension and bytes. Collisions receive a numeric suffix.
- Completed files survive interruptions; resume the remaining files. Keep the app in the foreground during downloads.

HRZ downloads and full telemetry analysis are not included. Device-reported lap counts and best laps do not establish that every lap followed a complete route.

### 1. Prepare

You need a Mac, an iPhone, a USB data cable and your own Apple account. Connect the Mac and iPhone to regular Wi-Fi with internet access during initial setup.

Download [SoloPocket-0.1.5.ipa](https://github.com/Tianyang-Zhang/solo-pocket/releases/download/v0.1.5/SoloPocket-0.1.5.ipa). If AltStore and Remote AltServer are already configured, skip to step 4. The release also includes `SHA256SUMS`. Download the `.ipa` asset, not the source-code ZIP.

### 2. Install AltStore Classic using your Mac

1. Download AltServer from the [official macOS installation page](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos), move it to Applications and launch it. Its icon appears in the menu bar.
2. Connect and unlock your iPhone using USB. Tap **Trust** when asked to trust the computer.
3. Select your iPhone in Finder. Under General, enable **Show this iPhone when on Wi-Fi**, then click Apply.
4. Click the AltServer menu-bar icon → **Install AltStore → your iPhone**. Enter your Apple account and complete verification.
5. On iPhone, open **Settings → General → VPN & Device Management**. Select your developer account and trust it.
6. Open **Settings → Privacy & Security → Developer Mode**, enable it, and follow the restart and confirmation prompts. Then open AltStore.

### 3. Set up Remote AltServer and LocalDevVPN

Use AltStore Classic 2.3 or later with Remote AltServer support, and update AltServer on your Mac.

1. Keep the iPhone connected to your Mac with AltServer running.
2. On iPhone, open **AltStore → Settings → Remote AltServer → Set up Remote AltServer…**.
3. Follow the setup wizard to pair with the computer and install **LocalDevVPN** through its provided link.
4. Open LocalDevVPN, allow the VPN configuration and connect.
5. Finish setup in AltStore. If prompted, select an available server under **Choose Server**.
6. With regular internet-connected Wi-Fi and LocalDevVPN enabled, try **My Apps → Refresh All**.

After setup, normal installation and refresh do not require your own Mac to be online. If a remote server is unavailable, try later or choose another one. If setup completes but connection still fails, the official guide recommends restarting the phone. [Remote AltServer documentation](https://faq.altstore.io/altstore-classic/remote-altservers)

### 4. Install or update Solo Pocket

1. Save `SoloPocket-0.1.5.ipa` in the iPhone Files app. Download it directly on the phone or send it from your Mac using AirDrop. **Keep the `.ipa` extension; do not unzip it.**
2. Stay connected to regular Wi-Fi with internet access and enable LocalDevVPN.
3. Open **AltStore → My Apps → +** in the upper-left corner and select the IPA.
4. If prompted, use the same Apple account used for AltStore. Wait for signing and installation, then open Solo Pocket.

For future updates, import the new IPA using the same account and install over the existing app. **Do not delete Solo Pocket first**, because this can delete its unbacked-up local files.

### 5. Choose a download folder

In Solo Pocket, open **设置 → 本地下载目录 → 选择本地父文件夹** (Settings → Local download directory → Choose local parent folder). Select a writable folder under **On My iPhone**.

The default location is **Files → On My iPhone → Solo Pocket → Solo Sessions**. Changing the parent folder affects only new batches; existing batches remain in their original locations.

```text
Solo Sessions/
  2026-10-11_Tom_KTM_390_Duke/
    Tom_2026-10-11_16-55-28.xrz
    Tom_2026-10-11_16-40-00.xrz
    batch.json
    sessions.csv
```

These are naming examples. Dates and times come from the session recording, not the download time. Batches spanning multiple days use a date range. Duplicate names receive `_2`, `_3`, and so on. The batch title and notes are stored in metadata.

### 6. Connect to Solo and download

1. **Turn LocalDevVPN off.** Quit AimMac if it is connected to the Solo.
2. Turn on the Solo and join its displayed AiM network under **iPhone Settings → Wi-Fi**. This network normally has no internet access.
3. Open **Solo Pocket → Solo → 读取 session 列表** (Read session list). Allow local-network access when prompted. Connection checks run automatically; no separate diagnostic step is needed.
4. Select sessions → **下载所选** (Download selected). Enter one batch title, driver, vehicle and optional notes. Review the folder and filenames, then start downloading.
5. Keep the app in the foreground. Downloads pause in the background and can be resumed after returning.
6. Find completed files in **本地批次** (Local batches) or the system Files app.

Google Drive setup is not required. The current release correctly shows that Google Drive is unconfigured. To enable it, configure your own Google OAuth client and rebuild; see the [development guide](docs/DEVELOPMENT.md).

### 7. Keep the app working

Free signing expires after **7 days**. Before expiration, connect to regular internet-enabled Wi-Fi, enable LocalDevVPN and tap **AltStore → My Apps → Refresh All**. Confirm that both AltStore and Solo Pocket have renewed expiration dates. AltStore attempts background refresh, but manually check before heading to the track. [AltStore expiration documentation](https://faq.altstore.io/altstore-classic/your-altstore)

| Action | iPhone network | LocalDevVPN |
| --- | --- | --- |
| Remote install, update or refresh | Wi-Fi with internet access | On |
| Read or download from Solo | Solo Wi-Fi | Off |
| View downloaded files | No network required | Not needed |

If AltStore itself has expired and cannot open, reinstall AltStore from your Mac using AltServer and the same Apple account, then refresh. Keep Solo Pocket and its local data installed.

### Troubleshooting

- **app in invalid format:** Download the IPA from this release again. Do not select the source ZIP or an extracted folder.
- **-80045:** This code alone does not identify the cause. Keep the full error message and try the local Mac AltServer installation path. Do not start by deleting the app.
- **Session-list timeout:** Check the Solo Wi-Fi connection, turn VPN off, close AimMac's connection, and check **Settings → Privacy & Security → Local Network → Solo Pocket**. Cellular Data is a different permission. Use **导出最近连接日志** (Export recent connection log) if it still fails.
- **Another Solo device does not connect:** 0.1.5 no longer checks its name. Use the device's Wi-Fi access-point mode. If a handshake or data-format error remains, export the log to identify model/firmware protocol differences.

### Source and release notes

See the [development guide](docs/DEVELOPMENT.md) for builds, tests and optional Google Drive configuration. Public fixtures are synthetic; personal downloaded recordings and connection logs are not included. Version 0.1.5 is rebuilt from this repository and retains handshake, file-length and checksum validation. See [release notes](docs/RELEASE-0.1.5.md) for test results and validation scope.
