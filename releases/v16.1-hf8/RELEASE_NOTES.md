# v16.1-hf8-r2（code46）测试预发布

## 下载

- APK: sisensing-eco-v16.1-hf8-code46-r2.apk
- SHA-256: 538c786914bbbf6d514280701cbb26afe2da4ea5346e98cad2a65ad984aa1797
- 大小: 58,573,859 bytes
- 包名/版本: com.sisensing.eco, 02.23.01.00-v16.1-hf8, versionCode=46
- 签名证书 SHA-256: efc23cb150fac98a6b45d93fc0914794b778e542fed6ff7c21925eab824dba8c

## 变更

- 将扫描收敛为单个幂等 PendingIntent scan lease，Alarm 只做租约健康检查。
- 对扫描状态码 6 设置 120 秒初次冷却和 300 秒重复冷却。
- 分离内部传输清理与显式用户暂停；拒绝旧 generation 回调影响当前状态。
- 连接状态先验证有效算法数据，数据事件按分钟聚合。
- 增加 connectedDevice 前台服务守护，并在 r2 中修正 Android 12/14 条件差异及 rejected-start sticky 回归。
- 保持未知算法 fail-closed 和 hf6 分享/资料页保护。

## 验证边界

自动检查 5/5、最终 APK 反编译/DEX/签名通过。MuMu Android12 覆盖安装与前台服务 >60 秒验证通过，5 轮冷启动无本轮 ANR/crash 日志。MuMu 不含真实探头；截至发布日期没有 hf8 真探头长时间测试，这不是稳定版或医疗可靠性声明。

本项目非官方。安装前阅读 [hf8 安装说明](../../docs/HF8_INSTALL.md)、[测试范围](../../docs/HF8_TESTING.md) 和 [限制](../../docs/HF8_LIMITATIONS.md)。不适合作为唯一健康监测依据。
