# hf8-r2 安装与使用

## 1. 先确认是否适合安装

hf8-r2 是非官方测试版，已过模拟器与静态/模型检查，**尚未完成真实探头长时间灭屏重连验收**。优先在备用测试设备验证，不建议用未经验证的修改版承担唯一监测任务。新版本代码旨在修复前版缺陷，不代表对未来探头或所有三星系统均兼容。

安装前记录现有 App 版本、确认账号登录方式，使用 App 支持的导出/备份方法保留重要数据，并准备可靠的替代监测方式。备份不一定能恢复探头会话。不要为了测试解绑当前探头、反复开关蓝牙或清除 App 数据。

## 2. 手机直接下载并安装

1. 在手机浏览器打开 [hf8 Release](https://github.com/tianming937/sisensing-eco-ble-reconnect-hf5/releases/tag/v16.1-hf8)。这是公开仓库，普通下载不要求 GitHub 登录。
2. 点击 `sisensing-eco-v16.1-hf8-code46-r2.apk`，或使用 [直达 APK 链接](https://github.com/tianming937/sisensing-eco-ble-reconnect-hf5/releases/download/v16.1-hf8/sisensing-eco-v16.1-hf8-code46-r2.apk)。不要下载 Source code ZIP 来安装。
3. 等待下载完成，文件约 55.9 MiB。按下方校验值核对文件身份，避免第三方网盘或转发包。
4. 在下载列表打开 APK。如果 Android 要求允许此浏览器/文件管理器安装应用，阅读提示并自行决定是否授予；完成后可撤销此来源的安装权限。
5. 系统显示“更新”时，再确认版本和应用身份后安装。系统阻止安装、提示签名冲突或不兼容时，**停止并核对，不绕过签名/安全检查**。
6. 打开 App，在系统“应用信息”或 App 版本页确认 `02.23.01.00-v16.1-hf8 / 46`。`r2` 不在版本名内，必须靠下载文件哈希区分 r1/r2。

直接下载后仍需由你确认安装，网页不能静默覆盖手机 App。GitHub 访问较慢时可先在电脑下载，再通过 USB 传到手机；传输后重新核对大小和哈希。

## 3. 能否不卸载覆盖

| 当前安装情况 | 处理方式 |
|---|---|
| 同包名、证书指纹相同、versionCode ≤ 46 | 具备保留数据更新的条件；实际仍需检查数据迁移与探头恢复 |
| 官方原版或其他证书签名的修改版 | 不能直接覆盖；停止，不自动卸载、不清数据 |
| code46 的 hf8-r1 测试包且同证书 | 可尝试同版本码覆盖 r2；必须校验 r2 哈希 |
| 高于 code46 的版本 | 不建议降级，不提供强制降级流程 |
| 不知道版本/证书 | 先核对，不凭文件名或“Android Debug”文字判断 |

覆盖安装保留数据是 Android 更新机制的预期，不是所有历史数据都绝不会出问题的承诺。`INSTALL_FAILED_UPDATE_INCOMPATIBLE` 通常提示签名不兼容；不要把“卸载重装”当作默认解决方案。卸载可能丢失登录、绑定和历史记录。

确需全新安装时，应先确认数据备份和探头能否重新接续，再由你自行决定卸载旧版；本项目脚本不会替你卸载。

## 4. 首次打开与连接

1. 确认蓝牙开启，按系统提示授予“附近的设备/蓝牙”和通知权限；不同 Android 版本的权限名称可能不同。
2. 首次重启后解锁手机并打开一次 App，确认正常登录与当前活动探头。hf8 在前台服务条件不满足时会安全停止；不能把“不崩溃”误当成“后台已连接”。
3. 在系统允许范围内检查电池后台策略、三星休眠名单。不要为了本项目关闭整机安全功能。
4. 先在前台确认新数据持续到达、时间戳前进。出现“连接成功”动画不等于已收到新数据；hf8 增加了数据验证阶段。
5. 如处于扫描限流冷却，首次约 120 秒，30 分钟内重复限流可能等待 300 秒；不要连续点击连接。
6. 未知算法会拒绝计算，而不是套用默认算法。此时应停止依赖修改版输出并反馈脱敏版本信息，不能保证未来每个新探头都能工作。

## 5. 在有备用监测安排下验收

先完成普通功能检查：登录、当前读数刷新、趋势页、血糖分享页面、个人中心→修改资料。无须为了测试发送短信、修改分享关系或保存资料。

真实 BLE 验收需记录：距离离开/返回时刻、屏幕状态、首次目标发现、GATT 连接、服务发现、首条有效且时间戳持续前进的数据。以自然距离造成断连，不是反复切换蓝牙。分别测试短离开、中等离开和长时间灭屏；恢复前不要点亮屏幕或手动连接，否则不能算纯灭屏恢复。

仅 `STATE_1` 不是完整成功证据；应结合 `CONNECTION_VERIFIED_VALID_DATA_HF8`、屏幕状态和后续新数据。若持续无数据或崩溃，不要继续压力测试主力监测设备；保存脱敏诊断并使用备用方案。

## 6. 可选：电脑 ADB 安装

先自行启用 USB 调试并在目标手机确认授权。`SERIAL` 必须替换为 `adb devices -l` 中明确确认的目标，避免安装到另一台设备。

```powershell
adb devices -l
adb -s SERIAL shell dumpsys package com.sisensing.eco
adb -s SERIAL install -r --no-incremental "sisensing-eco-v16.1-hf8-code46-r2.apk"
```

不使用 `pm clear`、卸载命令或强制降级参数。当前系统若拒绝覆盖，停止核对原因。

## 7. 校验下载文件

APK SHA-256：

```text
538c786914bbbf6d514280701cbb26afe2da4ea5346e98cad2a65ad984aa1797
```

文件大小 `58,573,859` 字节，签名证书 SHA-256：

```text
efc23cb150fac98a6b45d93fc0914794b778e542fed6ff7c21925eab824dba8c
```

Windows：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '.\sisensing-eco-v16.1-hf8-code46-r2.apk'
.\scripts\verify-hf8-apk.ps1 -Apk '.\sisensing-eco-v16.1-hf8-code46-r2.apk' `
  -BuildToolsDir 'D:\Android\Sdk\build-tools\36.0.0' -JavaHome 'D:\tools\jdk-17'
```

Linux/macOS 可使用 `sha256sum` / `shasum -a 256`。哈希仅证明文件身份，不证明医疗可靠性。

## 8. 诊断与回退

hf8 自有审计目录为 `/sdcard/Android/data/com.sisensing.eco/files/ble_audit_hf8/`。可在自己授权的设备上执行只读命令：

```powershell
adb -s SERIAL shell ls -la /sdcard/Android/data/com.sisensing.eco/files/ble_audit_hf8
adb -s SERIAL logcat -d -v threadtime -s SiSensingBLEv16:I AndroidRuntime:E
```

自有审计尽量不记录业务标识，但厂商/系统日志可能包含隐私。不要原样上传日志、bugreport、数据库或截图，先按 [贡献指南](../CONTRIBUTING.md) 脱敏。

保留安装前原包并不等于可以无损降级：版本码、签名和数据格式会影响回退。不要自行用卸载/清数据解决回退失败。先停止试验并确认数据和替代监测，再决定处置。
