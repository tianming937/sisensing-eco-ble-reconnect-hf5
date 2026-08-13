# 硅基轻享 BLE 断线重连补丁 v16.1-hf5

这是一个面向“硅基轻享”Android App 的非官方增量补丁项目，集中解决 BLE 探头在离开手机、长时间断连、灭屏和弱信号场景下难以自动恢复的问题，并为已知探头算法增加兼容修复和未知算法保护。

> [!CAUTION]
> 本项目不是硅基官方项目，不是经监管机构批准的医疗器械软件，也不提供诊断或治疗建议。App 无读数、读数异常，或身体症状与读数不一致时，请立即使用指尖血糖仪或其他可靠方式复核，并按医生给出的方案处理。不要把本修改版作为唯一健康依据。

## 这个版本能达到什么效果

v16.1-hf5 在 v15 的 xDrip/AAPS 桥接和兼容修复基础上，增加或保留了以下能力：

- BLE 断线后持续进行有界自动重试，不再因为扫描错误或 SDK 服务断开进入“永久停止重连”的死状态。
- 灭屏时使用真实的非空 Android `ScanFilter`，允许系统在屏幕关闭后继续处理 BLE 扫描结果。
- 亮屏使用兼容性更好的全通过扫描，灭屏使用“完整设备名、兼容短名称、服务 UUID”三个 OR 条件过滤器，并继续由原 SDK 做末四位二次匹配。
- 对扫描、连接过渡态设置 75 秒看门狗；卡住后执行限频软复位，而不是无限转圈。
- 采用 1.5/5/15/30/60/120 秒封顶的退避节奏，兼顾恢复速度、耗电和 Android 蓝牙栈压力。
- `LocalBleService` 和 SDK `ProximityService` 使用 `START_STICKY`；任务移除时不主动结束 SDK 服务。
- BLE 已显示连接但 12 分钟没有有效新数据时触发健康恢复；30 分钟内最多执行两次，避免复位风暴。
- 隐私安全的本地诊断环形日志，最多 200 条，不记录血糖值、手机号、令牌、MAC 地址或完整探头名称。
- 修复四套当前内置探头算法的加载路径，并在实例化前做类校验：
  - `ALGORITHM V1.1.2E(2024_02_29)`
  - `ALGORITHM E1.1.2G(2024_05_15)`
  - `ALGORITHM E1.1.5M(2025_1_16)`
  - `ALGORITHM E1.1.5N(2025_09_02)`
- 未知、空、`null` 或校验失败的算法一律拒绝计算，不再默认套用另一套算法，避免产生看似正常但实际错误的血糖结果。
- 保留此前的短信登录、密码登录和部分 Android 类校验热修复。

本项目不改变 BLE 协议、GATT UUID、原生血糖算法、血糖单位换算、账号接口或数据库结构。

## 真机验证结果

在一台三星 SM-S9180（Android 16）上，安装 `02.23.01.00-v16.1-hf5` 后，对约 55 小时可核验窗口进行了系统 Bluetooth GATT 历史、App 本地重连日志、屏幕状态和进程退出记录的交叉分析：

| 指标 | 结果 |
|---|---:|
| 可识别断连 | 36 次 |
| 最终自动恢复 | 36/36 |
| 首次重试发生在灭屏状态 | 19 次 |
| 灭屏场景最终恢复 | 19/19 |
| 恢复耗时中位数 | 35.3 秒 |
| 最长恢复耗时 | 11 分 44 秒 |
| hf5 安装后算法 `VerifyError` / `SIGABRT` / ANR | 0 |

这些是单个设备、单个环境下的观察结果，不是对所有手机、系统版本、射频环境或未来探头的成功率承诺。实测连接 RSSI 中位数为 `-90 dBm`，最差 `-103 dBm`；弱信号仍会导致反复断连和较长恢复。软件重试不能突破蓝牙射频物理限制。

详细证据和判定边界见 [测试报告](docs/TESTING.md)。

## 版本信息

| 项目 | 值 |
|---|---|
| 包名 | `com.sisensing.eco` |
| `versionCode` | `37` |
| `versionName` | `02.23.01.00-v16.1-hf5` |
| `minSdk` / `targetSdk` | `21 / 34` |
| 已验证架构 | `arm64-v8a`、`armeabi-v7a`（算法库由合法基线提供） |
| 本地最终测试包 SHA-256 | `C70316F72234908FD722FDC63A5FBB406A13F4B95D53A6296270831A1464DDA2` |
| 本地测试签名证书 SHA-256 | `efc23cb150fac98a6b45d93fc0914794b778e542fed6ff7c21925eab824dba8c` |

仓库不会提供上述测试 APK、厂商 APK、厂商签名、测试签名私钥、完整反编译源码或原生算法库。SHA-256 只用于识别本地已验证制品，不能证明医疗可靠性。

## 仓库内容

```text
.
├── patches/
│   └── v16.1-hf5-over-v15.patch   # 从本项目 v15 解包基线升级到 hf5
├── scripts/
│   ├── apply-and-build.ps1        # 校验、应用补丁并用 Apktool 构建
│   ├── sign-apk.ps1               # zipalign + 使用你自己的密钥签名
│   └── verify-apk.ps1             # 版本、对齐、签名和 SHA-256 校验
├── docs/
│   ├── INSTALL.md                 # 详细安装、首次使用和验收步骤
│   ├── BUILD.md                   # 构建基线、依赖和命令
│   ├── DESIGN.md                  # 重连状态机与算法保护设计
│   └── TESTING.md                 # MuMu/三星真机验证及已知限制
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── NOTICE.md
└── LICENSE
```

## 快速开始

### 普通使用者

由于本仓库不分发第三方 APK，你需要从自己信任且有权分发的构建者处取得 APK，或者按照 [构建文档](docs/BUILD.md) 自行构建。安装前务必先阅读 [详细安装与使用说明](docs/INSTALL.md)，尤其是签名不一致会导致无法覆盖安装、卸载会清空本地数据这一点。

ADB 覆盖安装仅适用于“包名相同、签名证书完全相同、目标 `versionCode` 不低于当前版本”的情况：

```powershell
adb install -r "path\to\sisensing-v16.1-hf5-signed.apk"
```

如果签名不一致，Android 会返回 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。不要用绕过签名校验的工具；应先确认备份和替代监测方案，再决定是否卸载旧版后安装。

### 构建者

准备好你有权使用的 v15 解包基线后：

```powershell
.\scripts\apply-and-build.ps1 `
  -BaseProject "D:\path\to\decoded-v15-project" `
  -OutputProject "D:\work\sisensing-hf5" `
  -ApktoolJar "D:\tools\apktool_2.9.3.jar" `
  -JavaExe "C:\Program Files\Java\jdk-17\bin\java.exe"
```

然后使用你自己的签名密钥：

```powershell
.\scripts\sign-apk.ps1 `
  -UnsignedApk "D:\work\sisensing-hf5-unsigned.apk" `
  -OutputApk "D:\work\sisensing-hf5-signed.apk" `
  -Keystore "D:\private\release.jks" `
  -Alias "release" `
  -BuildToolsDir "D:\Android\Sdk\build-tools\36.0.0"
```

脚本不会生成、读取或上传本项目维护者的签名私钥。完整先决条件和基线说明见 [BUILD.md](docs/BUILD.md)。

## 安装后的正确验收方式

1. 确认版本为 `37 / 02.23.01.00-v16.1-hf5`。
2. 允许“附近的设备/蓝牙”和通知权限，将电池策略设为“不受限制”，并加入三星“从不自动休眠的应用”。
3. 正常登录、绑定当前探头，确认前台能稳定收到新数据。
4. 让手机保持灭屏，通过自然走远造成断连，再带探头回到蓝牙范围；不要为了测试反复开关蓝牙。
5. 在不亮屏、不打开 App 的情况下等待恢复，然后查看诊断：

```powershell
adb logcat -v threadtime -s SiSensingBLEv16:I SiSensingAlgoHF5:E AndroidRuntime:E
```

出现 `FILTERED_SCAN_SCREEN_OFF_MULTI_HF4`，且之后进入连接/服务发现/有效数据状态，才可认定为灭屏自动恢复。亮屏后才开始重连不算灭屏成功。

## 已知边界

- MuMu 没有真实 BLE 探头，只能验证安装、启动、界面、类加载、算法加载和保护分支，不能替代真机 BLE 验收。
- 极弱信号、探头未广播、探头寿命结束、系统蓝牙栈故障或同一探头被另一部手机占用时，重连仍可能缓慢或失败。
- 当前版本没有“断连超过 5 分钟”的用户告警；这是后续最值得增加的安全功能。
- 早期 hf5 真机记录中曾出现与 BLE 无关的 `xq2`/ViewPager2 趋势页类校验异常；后续观察窗口未再出现，但该 UI 路径不能被视为已彻底修复。
- 未来探头若使用新的算法标识，本版本会安全拒绝计算并记录错误，而不是猜测算法；需要新增明确适配后才能读数。
- 使用自己新生成的签名构建 APK 时，不能覆盖任何由其他证书签名的官方版或修改版。

## 开源和第三方权利

仓库中的原创脚本、原创文档和原创补丁逻辑按 [MIT License](LICENSE) 发布。补丁上下文中可能出现为定位修改所必需的第三方符号或少量上下文；它们的权利仍归各自权利人。完整厂商 App、资源、原生库、算法实现和商标不属于本项目，也不在 MIT 授权范围内。详见 [NOTICE.md](NOTICE.md)。

“硅基轻享”及相关名称可能是其权利人的商标。本项目与厂商不存在隶属、认证或背书关系。

## 参与贡献

提交问题前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。不要上传 APK、账号信息、手机号、令牌、完整 MAC 地址、完整探头编号、血糖历史、签名私钥或包含这些信息的日志。
