# hf8-r2 设计说明

本页说明项目 hf6/code44 基线上的 hf8-r2/code46 增量逻辑，不代表所有 Android 设备上的行为保证。完整补丁及文件指纹见 patches 目录。

## 重连状态路径

1. 进程/Service 恢复时，先检查 connectedDevice 前台服务条件；不满足或启动异常时记录匿名事件、停止服务并拒绝 START_STICKY。
2. 读取持久化用户意图：用户明确暂停则不扫描；否则进入断连协调流程。
3. 若扫描租约已存在，只检查租约健康度，不重启扫描。
4. 若处于扫描冷却期，则等待；首次 status=6 等待 120 秒，短窗口内重复则提升到 300 秒。
5. 未连接且无租约时，创建一次 PendingIntent scan。命中已知目标后交回原 SDK 完成连接和算法匹配。
6. STATE_1 只是待验证；收到有效算法数据后才确认连接成功。

### 1. 一个扫描租约，不让唤醒源互相抢占

BlePendingScanHf7（历史类名）提供 hf8 的共享扫描租约。调用方检查租约状态，幂等 start() 不会先 stop 再 start。PendingIntent 结果解析 EXTRA_LIST_SCAN_RESULT 和错误码；只在有真实目标批次时触发后续路径。闹钟只检查租约健康度，不代替 SDK 直接建立第二个扫描。

Android 官方 BLE 指南建议命中目标后停止扫描、避免循环扫描并为扫描设置时限。hf8 的租约和退避是针对前版调度失控的工程约束；系统限流策略、射频和设备厂商行为仍可能不同。[Android BLE 设备发现指南](https://developer.android.com/develop/connectivity/bluetooth/ble/find-ble-devices)

### 2. 扫描状态码 6 的硬冷却

SCAN_FAILED_SCANNING_TOO_FREQUENTLY（数值 6）不按“普通未发现设备”处理。首次设置至少 120 秒冷却；30 分钟窗口内重复时提高到 300 秒。手动连接、Alarm、Handler 都不能清除冷却或绕过它；有效算法数据才清理 throttle history。Android API 对状态码的定义见 [ScanCallback](https://developer.android.com/reference/android/bluetooth/le/ScanCallback#SCAN_FAILED_SCANNING_TOO_FREQUENTLY)。

这些时长是 hf8 的保守策略，不是 Android 公开承诺的固定限流窗口。

### 3. 用户暂停和内部清理分离

原有 LocalBleService.s 仍表示显式用户暂停，并由明确的用户停止入口持久化。内部 transport teardown、切换连接、超时和扫描失败不再直接写该字段。收到迟到连接回调时再核对持久化用户意图，避免“内部清理=用户永久暂停”。Alarm generation 用于丢弃旧一轮恢复事件。

### 4. 连接确认分两步

底层 STATE_1 是 provisional 状态：先进入连接验证窗口，不立刻清除退避/限流记录。限定时间（6 分钟）内经过原有算法处理收到有效数据，才记为 CONNECTION_VERIFIED_VALID_DATA_HF8 并复位失败历史。有效数据日志按分钟聚合，不将数值写进这条审计流。

这只能证明数据解析路径近期有事件，不保证云端/显示值一定最新；验收还应看读数时间戳和持续更新。

### 5. 前台服务边界与 r2 修正

前台服务启动由 BleForegroundGuardHf8 统一处理：捕获 SecurityException/RuntimeException、用户未解锁或前置条件异常时停止服务；LocalBleService.onCreate() 把启动结果传播到 onStartCommand()，拒绝启动时返回非粘性，避免平台重复拉起造成崩溃循环。

**r1→r2 的差异：** r1 在 Android 12 上把 Android 14 才执行的 connectedDevice 类型权限检查提前了，导致服务未进入前台但调用路径仍保持粘性；MuMu 超时后出现前台服务 ANR。r2 将类型前置条件限定在 API 34+，并令被拒绝的启动不返回 START_STICKY。MuMu Android 12 的 74 秒前台门槛复测通过；Android 14+ 与三星系统仍需实机验证。[Android 前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types#connected-device)

### 6. 审计与隐私

hf8 使用独立的 ble_audit_hf8 目录，不向旧 hf7 日志追加。日志避免账户、token、完整探头名、MAC 和血糖数值，并聚合有效实体计数。系统 logcat/厂商 bugreport 可能包含其他敏感信息，不能把原始诊断文件直接公开。

### 已知限制

- BLE 广播、连接建立、服务发现、传感器生命周期和 Samsung 系统调度无法通过静态补丁或无探头模拟器证明。
- 前台服务成功存活不等于 BLE 已恢复；BLE 状态连接也不等于收到了新数据。
- 断连后探头不在范围、停止广播、已过期、被其他手机占用或系统蓝牙栈异常时，等待可能超过冷却期甚至失败。
- 不承诺“所有未来算法都支持”。未知算法应拒绝而非猜测，需有合法且明确的算法兼容更新。
- 不提供医疗诊断/治疗建议；发生读数缺失或症状不一致时，先使用可靠的备用测量与临床方案。
