# Solo Pocket 隐私说明 / Privacy notice

更新日期 / Updated: 2026-10-13

## 中文

Solo Pocket 将你选择的 AiM Solo 记录下载到 iPhone，并提供可选的 Google Drive 备份。使用本地下载、文件管理或分享不需要 Google 账号。

### 手机上的数据

设备记录、日期时间、圈数和圈速，以及你填写的车手、车型和备注，保存在你选择的本地目录。原始遥测文件可能包含 GPS 位置。连接诊断日志保存在手机上；只有你选择分享时才会发给接收方。App 没有开发者运营的遥测收集服务器，也不包含广告或独立的使用情况分析服务。

### 可选 Google Drive 备份

你通过 Google 的登录页面选择自己的账号并授权。Google Sign-In SDK 处理登录凭据和令牌，App 不读取你的 Google 密码。App 使用基本账号信息识别当前登录用户，并把该用户选择的上传目录保存在手机上。

App 请求 `drive.file` 权限，仅访问它创建或你授权给它的特定 Drive 文件。登录本身不会上传记录。只有你点击批次的上传按钮后，App 才会把该批次的原始记录和说明文件直接发送到你选择的 Google Drive 文件夹。说明文件包含该批次的记录信息及你填写的标注；导出的说明文件不包含 Google 登录令牌、账号标识或上传凭据。

开发者不会通过此功能接收你的记录，也不会把 Google 用户数据出售、用于广告或用于训练 AI 模型。Google 登录和云端存储同时受 [Google 隐私政策](https://policies.google.com/privacy)约束。Solo Pocket 对 Google API 数据的使用和传输遵守 [Google API 服务用户数据政策](https://developers.google.com/terms/api-services-user-data-policy)，包括 Limited Use 要求。

### 控制和删除

你可以在 App 设置中退出 Google 账号，或在 [Google 账号的第三方连接设置](https://myaccount.google.com/connections)撤销授权。退出或撤销授权不会删除已经保存的本地或云端文件。你可以分别在 iPhone「文件」及 Google Drive 中删除文件；手机上的批次状态和目录偏好会保留到 App 数据被删除。更换本地默认目录不会移动旧批次。上传不会删除本地原件。

如有隐私问题，请通过 [GitHub Issues](https://github.com/Tianyang-Zhang/solo-pocket/issues)联系维护者；公开问题中请不要附上私人记录、令牌或其他敏感资料。

## English

Solo Pocket downloads selected AiM Solo recordings to your iPhone and offers optional Google Drive backup. Local downloads, file management and sharing do not require a Google account.

### Data on your phone

Recordings, recording dates/times, lap counts/times and the driver, vehicle and notes you enter are saved in your chosen local directory. Raw telemetry may contain GPS locations. Connection diagnostics remain on the phone unless you choose to share them. The app has no developer-operated telemetry collection server, advertising or separate usage analytics service.

### Optional Google Drive backup

You choose and authorize your own account on Google's sign-in page. The Google Sign-In SDK manages credentials and tokens; the app does not read your Google password. Basic account information identifies the signed-in user, and that user's selected upload folder is stored on the phone.

The app requests `drive.file` access only for specific files it creates or you authorize. Signing in does not upload recordings. Only pressing a batch's upload button sends its original recordings and metadata directly to the selected folder in your Google Drive. Metadata includes recording details and your batch annotations; exported metadata excludes Google tokens, account identifiers and upload credentials.

The developer does not receive your recordings through this feature and does not sell Google user data or use it for advertising or AI training. Google sign-in and cloud storage are also governed by the [Google Privacy Policy](https://policies.google.com/privacy). Solo Pocket's use and transfer of Google API data adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including its Limited Use requirements.

### Control and deletion

Sign out in app settings, or revoke access in [Google Account connections](https://myaccount.google.com/connections). Neither action deletes saved local or cloud files. Delete files separately through iPhone Files and Google Drive; local batch state and folder preferences remain until app data is removed. Changing the default local directory does not move existing batches. Uploading never deletes the local originals.

For privacy questions, contact the maintainer through [GitHub Issues](https://github.com/Tianyang-Zhang/solo-pocket/issues). Do not attach private recordings, tokens or other sensitive information to a public issue.
