# hf8-r2 补丁源码与构建

## 发布模型与前提

本仓库只开源原创增量逻辑、脚本和文档，不提供厂商完整反编译工程或原生算法源码。Release 的 APK 包含第三方内容，不整体适用 MIT。普通用户可直接下载 APK，无须完成本页步骤。

源码补丁 `v16.1-hf8-over-hf6.patch` 合并了 hf6 code44 到 hf8-r2 code46 的变化，**不要求先发布、安装或应用 hf7**。代码中保留 `BleAuditHf7`、`BlePendingScanHf7`、`BleWakeSchedulerHf7` 等历史类名以维持调用兼容；其内容是 hf8 实现，日志目录已经改为 hf8。

必须自行准备有权使用的项目 hf6/code44 源码基线：

- 包名 `com.sisensing.eco`，版本 `02.23.01.00-v16.1-hf6 / 44`；
- `smali` 到 `smali_classes8` 八个业务 DEX 目录；
- 已包含 hf6 的分页、冷启动、分享和资料页修复；
- 保留 `kotlin/`、`META-INF/services/` 等原始兼容元数据；
- 被改文件和 Manifest 的标准化 SHA-256 必须匹配 `patches/hf8-source-manifest.json`。

这不是静态解包官方加固 APK 的通用补丁，也不是 hf5→hf8 补丁；仅靠本仓库不能独立构建厂商 App。不提供从第三方设备提取基线或绕过许可证的流程。刚从另一个工具/版本反编译得到的 hf6 文件标签和布局可能不同，脚本会拒绝；不要删掉指纹检查强行构建。

## 工具

- Windows PowerShell 5.1/7、Git；
- JRE/JDK 17；
- Apktool **2.12.0**（这是 hf8 工作流；旧 hf5 文档的 2.9.3 要求不适用）；
- Android SDK Build Tools 36.0.0（`zipalign`、`apksigner`、`aapt2`）；
- Python 3.10+ 仅用于补丁导出、源码/发布检查及 DEX 审计；安装 APK 不需要。

## 应用与构建

```powershell
.\scripts\apply-and-build-hf8.ps1 `
  -BaseProject 'D:\authorized\hf6-code44-project' `
  -OutputProject 'D:\work\hf8-project' `
  -ApktoolJar 'D:\tools\apktool_2.12.0.jar' `
  -JavaExe 'D:\tools\jdk-17\bin\java.exe' `
  -UnsignedApk 'D:\work\hf8-unsigned.apk'
```

仅应用、不构建时可用 `-PatchOnly`，省略 Java/Apktool 参数。输出目录必须全新，不能与输入嵌套；脚本拒绝覆盖已有输出。基线不被修改。

脚本先核对补丁、输入版本和指纹，执行 `git apply --check`，再复制源码输入到新目录；不复制 `build/`、`dist/`、`.git/` 和旧签名的 `original/`。应用后验证每个输出指纹，并把 7 个 Kotlin built-ins 与 8 个服务发现元数据从合法基线原样复制至 `unknown/`，避免干净构建丢失条目。它不下载或生成第三方算法库。

## 签名与验证

自行构建须使用自己的私钥；仓库不提供项目维护者或厂商私钥。

```powershell
.\scripts\sign-apk.ps1 -UnsignedApk 'D:\work\hf8-unsigned.apk' `
  -OutputApk 'D:\work\hf8-signed.apk' -Keystore 'D:\private\release.jks' `
  -Alias release -BuildToolsDir 'D:\Android\Sdk\build-tools\36.0.0' -JavaHome 'D:\tools\jdk-17'

.\scripts\verify-hf8-apk.ps1 -Apk 'D:\work\hf8-signed.apk' `
  -BuildToolsDir 'D:\Android\Sdk\build-tools\36.0.0' -JavaHome 'D:\tools\jdk-17' -AllowRebuilt
```

密码由 apksigner 交互询问，不放进脚本参数/仓库。`-AllowRebuilt` 仅允许自建包的哈希和证书不同，仍检查包名、版本、签名有效性和对齐；**校验公开下载包不要加此参数**。自己生成的证书不能覆盖其他证书签名的 App。

不是 bit-for-bit 可复现构建承诺：ZIP 时间戳、工具版本、签名都会改变 APK 哈希。最终发布的是已测试的 r2 APK，不是本次验证所产出的未签名重建包。

## 测试

```powershell
.\tests\verify_hf8_static.ps1 -Project 'D:\work\hf8-project'
.\tests\test_hf8_reconnect_model.ps1
.\tests\test_paging_model.ps1
.\tests\test_share_guard_model.ps1

& 'D:\tools\jdk-17\bin\java.exe' -jar 'D:\tools\apktool_2.12.0.jar' d `
  'D:\work\hf8-signed.apk' -o 'D:\work\hf8-final-decoded'
.\tests\verify_hf8_final_decompiled.ps1 -DecodedProject 'D:\work\hf8-final-decoded'
python tests\verify-hf8-publication.py
```

模型不执行 Android Smali、无线协议或真实探头算法，只验证抽象策略；静态检查和反编译检查也不替代真机。真实测试矩阵见 [HF8_TESTING.md](HF8_TESTING.md)。

## 维护者重建补丁

```powershell
python scripts\export-hf8-patch.py --base 'D:\authorized\hf6-code44-project' `
  --target 'D:\authorized\hf8-r2-project' --output 'D:\work\hf8-patch-export'
```

导出器检查整个源码树的变更白名单（排除构建缓存、原签名目录），只允许 6 个修改、4 个新类和 15 个兼容元数据复制项。只把文本增量与哈希清单输出到公开补丁，不复制厂商二进制、资源、账户和日志。输入项目仍需可信且有权使用。
