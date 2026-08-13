# 贡献指南

欢迎提交可复现的问题、文档修正和增量补丁。这个项目涉及健康数据和闭源第三方应用，请遵守以下边界。

## Issue 最少信息

- 手机厂商、型号、Android/One UI 版本；
- 补丁版本、`versionCode` 和 APK SHA-256；
- 安装方式：全新安装或覆盖安装；
- 当前探头算法标识；
- 断连发生时屏幕状态、离开时长和大致距离；
- 从断连到恢复的时间线；
- 已脱敏的 `SiSensingBLEv16` / `SiSensingAlgoHF5` 日志。

## 严禁上传

- 官方或修改版 APK、完整反编译工程、原生算法库；
- 签名私钥、keystore、密码或 token；
- 手机号、账号、完整 MAC、完整探头编号；
- 血糖历史或任何可识别个人的健康数据；
- 未经权利人许可的第三方资源。

日志中的设备名称和地址应替换为不可逆的占位符，例如 `PROBE_1` 和 `XX:XX`。保留事件顺序、时间间隔、状态码和 RSSI 即可。

## 修改要求

- 优先最小增量，不改变 BLE 协议、认证或血糖算法。
- 每个恢复路径必须有频率上限，避免扫描/连接风暴。
- 未知算法必须失败关闭（fail closed），禁止猜测或默认套用。
- 诊断日志不得记录血糖值、账号、令牌、MAC 或完整探头名称。
- 提交前执行补丁应用检查、Apktool 构建、zipalign、apksigner 验证，并在模拟器完成冷启动烟雾测试。
- 真机 BLE 结论必须说明屏幕状态、样本量和局限，不能把一次成功写成“完全解决”。

## 提交格式

建议使用 Conventional Commits：

```text
fix(ble): recover after scan callback failure
docs(install): clarify signature mismatch handling
test(algorithm): cover unknown identifier guard
```
