# hf8-r2 测试范围与结果

日期以 Asia/Shanghai 为准。报告区分静态/模型、MuMu 与真探头实测，不把其中一种证据替代另一种。

## 自动回归与成品审计

2026-11-08 在 hf8-r2/code46 成品和项目源码上执行：

| 检查 | 结果 |
|---|---|
| verify_hf8_static.ps1 | PASS；版本、冷却、租约、用户暂停所有权、FGS、防护、数据验证、分享/资料/未知算法不变量 |
| verify_hf8_final_decompiled.ps1 | PASS；针对签名后 r2 APK 反编译核对，不只检查工程输入 |
| test_hf8_reconnect_model.ps1 | PASS；100 次扫描调度幂等、冷却、暂停隔离、旧 generation 与有效数据确认 |
| test_paging_model.ps1 | PASS；有界分页、游标校验和退避模型 |
| test_share_guard_model.ps1 | PASS；鉴权、单飞、请求冷却和 stale lock 模型 |
| 最终 APK 对齐/签名/metadata | PASS；v1/v2/v3，code46、hf8、包名正确 |
| 8 个 DEX 审计 | PASS；229,845 个有代码方法；全零 code 方法 0；检测到的异常结构 0 |

这些自动检查没有执行厂商 BLE SDK、手机系统蓝牙堆栈、传感器射频或算法有效性，因此不是实机 BLE 成功证明，也不是医疗软件认证。

## MuMu Android 12 验证

使用 MuMu 主实例 0，ADB 127.0.0.1:16384，Android 12 / API 32：

- 用 adb install -r --no-incremental 将 r2 覆盖安装到已有 hf7 环境，安装成功；测试设备上保留的数据没有清除。
- 清理本轮模拟器 logcat 后冷启动，服务运行跨过 60 秒门槛，约 74 秒后 dumpsys activity services 确认 LocalBleService isForeground=true、通知 ID 8888。
- 同一实例执行 5 轮强制停止后冷启动，进程均重新创建；第 5 轮持续观察超过 2 分钟，AndroidRuntime:E / ActivityManager:E 查询无本轮输出。
- App 登录页显示正常；空验证码输入未触发此次测试范围内的崩溃。
- 审计日志记录 RESTORE_WAIT_SESSION_HF6 和周期性健康检查；模拟器没有账户会话和真实探头。

**先前 r1 缺陷及 r2 处理：** r1 同样检查 FGS 的 connectedDevice 前置条件，但错误地在 API 32 提前要求 Android 14 类型权限；服务创建中止后粘性启动仍可能保留，出现前台服务超时 ANR。r1 不作为发布附件。r2 将该条件限定 API34+，并且 FGS 未就绪时 onStartCommand() 停止服务并返回 START_NOT_STICKY。上述 74 秒与多轮重启专门复核该路径。

## 真实手机/探头

截至本报告日期，没有 hf8-r2 的真实探头/三星长时间重连结果。MuMu 不能模拟真实 BLE 广播、Samsung BLE 限流或探头算法数据。因此本项目只能说 r2 的代码路径、成品完整性和模拟器 Service 烟雾测试已通过；不能说距离断连、灭屏或长时间离开已经实机解决。

之前 hf7 在 SM-S9180 的失败记录帮助确定要修复的错误码 6 扫描限流、用户暂停标志混用和 FGS 冷启动路径；这些数字是 hf7 的，不可以移用到 hf8。hf8 测试也不得据此描述为 100% 成功。

## 下一阶段真机验收清单

使用备用测试设备或已准备可信备用监测方式后再做：

1. 确认实际 APK hash、包名、code46 和签名；记录手机型号、Android/One UI 版本、探头代次/算法（脱敏）。
2. 确认前台连接并有新时间戳的数据；若系统还在冷却，记录剩余时间，不重复狂点。
3. 执行短离开、中离开、长离开三类距离断连；每轮灭屏回到范围，直到出现 CONNECTION_VERIFIED_VALID_DATA_HF8 和新鲜数据。
4. 至少观察 24 小时扫描失败状态码、连接验证超时、服务存活、App 崩溃和数据更新时间。
5. 单独验证亮屏手动连接、用户明确暂停、权限撤销/重新授权、重启解锁和新探头切换。
6. 记录断连→发现→GATT→服务发现→有效数据时间轴；屏幕关闭时成功重连才计为灭屏成功。

达到预定样本量前不要发布“可靠率/百分比”。出现无数据、异常值、Crash 或身体症状与读数不一致时，停止测试，优先用可靠方式处理健康问题。
