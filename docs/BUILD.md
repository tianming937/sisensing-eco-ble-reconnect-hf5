# 构建说明

## 1. 发布模型

这个仓库是“增量补丁工程”，不是完整 App 源码仓库。原因有两个：

1. v16.1-hf5 是在闭源厂商 APK 的运行时业务 DEX 基线上完成的 Smali 增量修复；
2. 完整 APK、反编译资源和原生算法库不属于本项目，不能被 MIT License 重新授权。

因此构建者必须自行准备一份有权使用的 v15 解包基线。补丁直接应用在该基线上，然后由 Apktool 重建。

## 2. 基线要求

补丁目标是本项目 v15 解包工程，而不是静态解包的官方加固 APK。正确基线具有：

- 包名 `com.sisensing.eco`；
- 官方业务版本 `02.23.01.00`、原 `versionCode=31`；
- 8 个 Smali 目录：`smali` 到 `smali_classes8`；
- 已恢复真实 `BaseApplication` 和 v15 的 xDrip/AAPS/数据库兼容补丁；
- 各目录类文件数应约为：7762、9160、6366、5999、2213、2449、2395、176；
- `AndroidManifest.xml` 与 v15 基线一致；
- 使用 Apktool 2.9.3 解包/重建。

官方静态 APK 受加固保护，直接执行 `apktool d` 通常只得到壳 DEX，不具备上述 8 个业务 Smali 目录。`apply-and-build.ps1` 会拒绝这种错误基线。

> [!IMPORTANT]
> 本仓库不提供绕过设备安全机制、取得第三方运行时 DEX 或规避许可证限制的自动流程。你必须自行确认基础材料来源和权限。

## 3. 工具

经本项目验证的工具：

- Windows PowerShell 5.1 或 PowerShell 7；
- JRE/JDK 17；
- Apktool 2.9.3；
- Android SDK Build Tools 36.0.0（`zipalign`、`apksigner`、`aapt`）；
- ADB（仅安装和验证需要）；
- Git 2.x。

Apktool 2.12.0 曾在这个由 2.9.3 生成的工程上出现 native 库重复打包兼容问题，因此正式复现使用 2.9.3。

## 4. 应用补丁并构建

在仓库根目录执行：

```powershell
.\scripts\apply-and-build.ps1 `
  -BaseProject "D:\authorized\sisensing-v15-decoded" `
  -OutputProject "D:\work\sisensing-v16.1-hf5" `
  -ApktoolJar "D:\tools\apktool_2.9.3.jar" `
  -JavaExe "C:\Program Files\Java\jdk-17\bin\java.exe" `
  -UnsignedApk "D:\work\sisensing-v16.1-hf5-unsigned.apk"
```

脚本会：

1. 验证基线目录结构和关键文件；
2. 验证补丁能以 `git apply --check` 干净应用；
3. 把基线复制到全新的输出目录，不修改输入基线；
4. 应用 `patches/v16.1-hf5-over-v15.patch`；
5. 确认 `versionCode=37` 和 `versionName=02.23.01.00-v16.1-hf5`；
6. 只在新输出副本中清除 `.bak`、`.orig` 或 `.rej` 残留，不改动输入基线，防止残留意外进入 APK；
7. 使用 Apktool 2.9.3 生成未签名 APK；
8. 输出 SHA-256。

如果 `OutputProject` 已存在，脚本会停止，避免覆盖用户文件。

脚本在应用补丁时忽略行尾空白差异，以兼容 Windows/Unix 换行；它不会忽略指令或方法体差异。

## 5. 签名

Android 要求所有 APK 签名。你有两种选择：

- 使用自己已有且与当前安装版本相同的密钥，以支持覆盖升级；
- 生成自己的新密钥，用于全新安装和后续自己维护的升级链。

新密钥示例：

```powershell
keytool -genkeypair `
  -keystore "D:\private\sisensing-community-release.jks" `
  -alias "sisensing-community" `
  -keyalg RSA `
  -keysize 3072 `
  -validity 3650
```

不要把 keystore 或密码放进仓库。

对齐并签名：

```powershell
.\scripts\sign-apk.ps1 `
  -UnsignedApk "D:\work\sisensing-v16.1-hf5-unsigned.apk" `
  -OutputApk "D:\work\sisensing-v16.1-hf5-signed.apk" `
  -Keystore "D:\private\sisensing-community-release.jks" `
  -Alias "sisensing-community" `
  -BuildToolsDir "D:\Android\Sdk\build-tools\36.0.0"
```

默认由 `apksigner` 安全地交互询问密码。脚本不接受明文密码参数，避免密码出现在 shell 历史和进程列表。

## 6. 验证制品

```powershell
.\scripts\verify-apk.ps1 `
  -Apk "D:\work\sisensing-v16.1-hf5-signed.apk" `
  -BuildToolsDir "D:\Android\Sdk\build-tools\36.0.0"
```

检查点：

- `zipalign -c -v 4` 成功；
- `apksigner verify --verbose --print-certs` 成功；
- 包名、版本码和版本名正确；
- 输出 SHA-256 和签名证书指纹；
- 不含 `.idsig` 也不影响普通 APK 安装；v4 侧载签名不是必需项。

本项目历史最终测试包通过 v1/v2/v3 签名验证和 4 字节 zipalign，SHA-256 为：

```text
C70316F72234908FD722FDC63A5FBB406A13F4B95D53A6296270831A1464DDA2
```

由于 APK 构建时间、ZIP 顺序和签名不同，自行构建通常不会产生相同哈希。应验证代码版本、签名身份、静态结构和运行行为，而不是把上述哈希当作可复现构建承诺。

## 7. 模拟器烟雾测试

先在 MuMu 或其他隔离模拟器测试，不要直接覆盖健康监测主力手机。

```powershell
adb -s 127.0.0.1:16384 install -r "D:\work\sisensing-v16.1-hf5-signed.apk"
adb -s 127.0.0.1:16384 shell am force-stop com.sisensing.eco
adb -s 127.0.0.1:16384 shell monkey -p com.sisensing.eco -c android.intent.category.LAUNCHER 1
adb -s 127.0.0.1:16384 logcat -d -v threadtime AndroidRuntime:E *:S
```

至少检查：

- 全新安装和从同签名前版覆盖安装；
- 连续 5 次冷启动；
- 短信/密码登录页面双向切换；
- 获取验证码空输入校验不崩溃；
- 进程持续存活且无 `VerifyError`、`FATAL EXCEPTION` 或 ANR；
- 四个已知算法类可加载，未知/空/`null` 标识安全返回空。

模拟器没有真实探头，不能验证扫描、GATT、认证、实时数据或灭屏恢复。

## 8. 补丁边界

相对 v15 基线，hf5 补丁只改变：

- `apktool.yml` 的版本字段；
- v16 重连监督器和 7 个 BLE/服务接入文件；
- v16.1/hf4 的灭屏扫描过滤器路径；
- hf2/hf3 的登录和界面类校验修复；
- hf5 的 3 个算法上下文、算法工厂和空对象释放保护。

补丁不会加入 APK、DEX、SO、资源或密钥。可用以下命令检查发布树：

```powershell
git ls-files | Select-String -Pattern '\.(apk|aab|dex|so|jks|keystore|p12|pem|key)$'
```

预期无输出。
