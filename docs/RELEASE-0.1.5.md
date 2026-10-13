# Solo Pocket 0.1.5

## 中文

取消仅允许 `Solo 2 Tom` 的设备名限制。连接你的 Solo Wi-Fi 后，直接读取列表；任意自定义设备名均可，无需改名或登记序列号。

- 发现回应不再按名字或文本编码匹配，读取、下载和心跳共用此行为。
- 保留 TCP 预检、本地网络授权、协议握手、帧校验和文件长度检查。
- 首页和设置改为当前 Wi-Fi 上的 Solo，不再显示作者设备的 Wi-Fi 名称。
- 首次使用不再预填作者姓名；升级后仍记住用户上次填写的车手和车型。
- 中英文 README 与中文 PDF 同步更新。

验证：26 项核心测试全部通过，包括任意中文名称、UTF-16 名称、非文本发现回应的读取及下载，以及握手不兼容时禁止继续发送读取命令。iPhone arm64 Release 编译与 IPA 结构检查通过。0.1.5 尚未在真实手机上重新安装测试，其它 Solo 型号和固件也未逐一实测。

适用范围：设备 Wi-Fi 接入点地址 `10.0.0.1`，且支持本程序的下载协议。解除设备名限制不代表已验证全部 Solo 型号；USB-only 设备不在此 Wi-Fi 流程范围内。Google Drive 仍可选且未配置 OAuth。

使用原 Apple 账号在 AltStore 覆盖安装，保留原 App 数据。

## English

Removes the discovery restriction to `Solo 2 Tom`. Join your Solo Wi-Fi and read sessions with any custom device name; no renaming or serial registration is required.

- Discovery no longer matches owner names or assumes a text encoding. Reads, downloads and heartbeats use the same behavior.
- TCP preflight, local-network permission handling, protocol handshake, frame checksums and length validation are preserved.
- Connection instructions refer to the current Solo Wi-Fi instead of the author's network.
- New installations start with an empty driver field; existing saved driver/vehicle preferences remain intact.
- Chinese and English README instructions and the Chinese PDF are updated.

Validation: all 26 core tests passed, including list/download flows for arbitrary Chinese names, UTF-16 names and opaque discovery replies, plus rejection of incompatible handshakes before any list/file command. The iPhone arm64 release build and IPA validation passed. Version 0.1.5 has not yet been reinstalled on a physical phone; other Solo models and firmware have not been individually tested.

Scope: a device using the supported download protocol at the default Wi-Fi access-point address `10.0.0.1`. Removing name restrictions does not establish compatibility with every Solo model. USB-only devices are outside this Wi-Fi workflow. Google Drive remains optional and OAuth is unconfigured.

Install over the existing app in AltStore using the same Apple account to keep local app data.

## Package

- Version: 0.1.5, build 6.
- Unsigned iPhone IPA for AltStore to sign.
- SHA-256: `9fb304c559f9bd91580b27c6140dcc34a8e01dd999dc564a050a803d80047c97`.
