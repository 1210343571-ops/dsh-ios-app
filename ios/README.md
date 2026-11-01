# DSH Mobile —— 原生 iOS 外壳（SwiftUI + WKWebView）

这是 DSH（DeepSeek Harness）移动方案的**原生 iOS 壳**：不重写桌面 UI，而是用 `WKWebView` 通过局域网把电脑上
DSH 桌面宿主的**完整 Web UI** 加载过来，同时用 SwiftUI 提供原生层的「多端点仪表盘 / 端点详情 / 更新检查 / Face ID 锁 / 深链配对」。

契约来源是仓库根 `docs/SPEC.md` 的第 2、6、8 节：网关 HTTP API、原生壳要求、升级与「官方更新 → iOS 同步」策略。
本目录只写 `ios/**`，不依赖任何第三方库（无 CocoaPods、无 SPM、无外部字体/网络资源）。

> **构建状态说明**：本目录是在 Windows 上写的，没有 `swiftc`/Xcode，**未在本机编译验证**。
> 已做的验证：`scripts/static-check.py`（project.yml 是合法 YAML、Info.plist 可被 plistlib 解析、
> Assets 的 Contents.json 合法且图标真实存在、29 个 Swift 文件经 tree-sitter-swift **语法解析**无 ERROR/MISSING 节点、
> 括号配平/无 TODO/无裸 `fatalError`/无 `try!`、所有 `t("...")` 文案在 zh-Hans 与 en 中齐全且键集合一致、
> 未使用 iOS 17 专属 API、workflow 是合法 YAML）。
> **这是语法层验证，不是类型检查**：真正的编译验证交给 GitHub Actions 的 macOS 14 runner（见下文 CI）。

## 目录结构

```
ios/
├── project.yml                     # XcodeGen 工程描述（唯一工程来源，.xcodeproj 不入库）
├── Sources/
│   ├── Info.plist                  # 手写 plist：ATS / Face ID / 局域网 / URL scheme
│   ├── DSHMobileApp.swift          # @main App，注入 Store，处理 onOpenURL 深链
│   ├── Models/
│   │   ├── Endpoint.swift          # 端点模型 + 地址归一化
│   │   ├── HostStatus.swift        # /__mobile/api/status 响应（全部字段可选）+ 端点快照
│   │   └── UpdateInfo.swift        # /__mobile/api/update 响应 + health
│   ├── Services/
│   │   ├── AppModel.swift          # 协调器：store 组合、深链配对、锁屏、前后台生命周期
│   │   ├── EndpointStore.swift     # 端点列表（UserDefaults 存 JSON）
│   │   ├── TokenStore.swift        # 设备令牌（Keychain，按 endpoint.id 分账户）
│   │   ├── PairingClient.swift     # POST /__mobile/api/pair
│   │   ├── StatusClient.swift      # GET health / status / update
│   │   ├── StatusCenter.swift      # 并发（allSettled 语义）拉全部端点 + 轮询
│   │   ├── UpdateChecker.swift     # 更新检查 + App 版本信息
│   │   ├── BiometricLock.swift     # LocalAuthentication（生物识别，失败退回设备密码）
│   │   └── SettingsStore.swift     # 语言 / 轮询间隔 / 设备名 / App Store ID / 锁屏开关
│   ├── Support/
│   │   ├── HTTPClient.swift        # URLSession async/await（10s 超时）
│   │   ├── NetworkSession.swift    # URLSession 配置
│   │   ├── JSONCoding.swift        # 容错 JSON 解码（日期多种格式）
│   │   ├── Formatters.swift        # 时间/时长/数字格式化
│   │   ├── L10n.swift              # 轻量本地化（跟随系统 / 手动切中英）
│   │   └── DSHLog.swift            # os.Logger 统一日志
│   ├── Views/
│   │   ├── RootView.swift          # 锁定态 / 主界面切换、全局 alert、scenePhase
│   │   ├── RootTabView.swift       # 四个 Tab：仪表盘 / 工作台 / 更新 / 设置
│   │   ├── DashboardView.swift     # 原生仪表盘（并发状态、下拉刷新、增删端点）
│   │   ├── EndpointDetailView.swift# 端点详情 + 打开工作台/控制台 + 更新检查
│   │   ├── AddEndpointView.swift   # 地址 + 6 位码配对
│   │   ├── WebWorkspaceView.swift  # WKWebView（注入 dshm_device Cookie）
│   │   ├── UpdateView.swift        # 宿主更新 + 原生 App 版本说明
│   │   ├── SettingsView.swift      # 安全 / 刷新 / 语言 / 关于 / 清空数据
│   │   ├── LockView.swift          # Face ID 锁屏
│   │   └── Components.swift        # 共用小组件
│   └── Resources/
│       ├── Assets.xcassets/        # AppIcon（1024 PNG，脚本生成）+ AccentColor
│       ├── zh-Hans.lproj/Localizable.strings
│       └── en.lproj/Localizable.strings
├── scripts/
│   ├── generate-project.sh         # xcodegen 包装
│   ├── static-check.py             # Windows 上可跑的静态自检
│   └── make-app-icon.py            # 重新生成 AppIcon（需要 Pillow）
├── .github/workflows/ios.yml       # CI（见「重要：workflow 位置」）
├── .gitignore
└── README.md
```

## 三种构建方式

### 方式 1：Xcode 直接打开（推荐日常开发）

```bash
cd ios
brew install xcodegen          # 只装一次
./scripts/generate-project.sh  # 生成 DSHMobile.xcodeproj
open DSHMobile.xcodeproj       # 选一个模拟器 ⌘R
```

`project.yml` 是唯一工程描述，`DSHMobile.xcodeproj` 不入库。改了文件/设置就重新 `xcodegen generate`。

### 方式 2：命令行 xcodegen + xcodebuild（无 GUI / CI 同款）

```bash
cd ios
xcodegen generate
xcodebuild -project DSHMobile.xcodeproj -scheme DSHMobile \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

### 方式 3：GitHub Actions CI

工作流文件是 `ios/.github/workflows/ios.yml`（按 SPEC 第 6 节放在 `ios/` 内）。
**GitHub 只执行仓库根目录的 workflow**，所以要用 CI 时先复制到根：

```bash
mkdir -p .github/workflows
cp ios/.github/workflows/ios.yml .github/workflows/ios.yml
```

它做三件事：

1. `macos-14` 上 `brew install xcodegen` → `xcodegen generate` → `xcodebuild ... -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO`
   （无需证书即可验证能否编译），并跑一遍 `python3 scripts/static-check.py`。
2. 上传模拟器产物 `DSHMobile-simulator-app` artifact。
3. 可选的 `archive` job：只有当仓库 secrets 里配好签名材料时才运行，产出 IPA；缺失时 `archive-skipped` job 会打印一条 notice 说明跳过原因。

签名 secrets（可选）：

| Secret | 内容 |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `.p12` 开发证书的 base64（`base64 -i cert.p12 \| pbcopy`） |
| `P12_PASSWORD` | `.p12` 的密码 |
| `PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `DEVELOPMENT_TEAM` | 10 位 Team ID |

## 签名与 TestFlight

1. Xcode → Settings → Accounts 登录 Apple ID（免费账号也能上真机，7 天有效）。
2. 打开工程，选中 `DSHMobile` target → Signing & Capabilities：
   - 勾选 *Automatically manage signing*；
   - Team 选你的开发者团队；
   - Bundle Identifier 默认 `com.deepseek.dshmobile`，已被占用就改成你自己的（如 `com.yourname.dshmobile`），
     同时改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER`，避免下次生成被覆盖。
3. 真机调试：连上 iPhone → 选择设备 → ⌘R。首次运行需在 iPhone「设置 → 通用 → VPN与设备管理」里信任开发者证书。
4. TestFlight：
   - 在 Xcode 里 Product → Archive；
   - Organizer 里 *Distribute App* → *App Store Connect* → *Upload*；
   - App Store Connect 建好 App 记录后，构建版本会出现在 TestFlight，添加测试员即可；
   - 上传前确认 `MARKETING_VERSION`（1.0.0）与 `CURRENT_PROJECT_VERSION`（构建号）已递增。
5. 备案/隐私：App 只访问局域网、不收集数据、不加密导出（`ITSAppUsesNonExemptEncryption=false` 已写在 Info.plist），
   但上架仍需按 Apple 要求填写隐私清单与局域网用途说明。

## 局域网 HTTP 与 ATS 说明（重要）

网关默认是**明文 HTTP**，形如 `http://192.168.3.18:63421`（端口默认 63421，见 SPEC 2.1）。
iOS 的 ATS 默认禁止明文 HTTP，本项目在 `Sources/Info.plist` 里这样处理：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key><false/>          <!-- 不全局放开明文 -->
    <key>NSAllowsLocalNetworking</key><true/>          <!-- 只放开「本地网络」 -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
            <key>NSIncludesSubdomains</key><true/>
        </dict>
    </dict>
</dict>
```

- **`NSAllowsLocalNetworking = true`**：允许访问局域网里的「本地资源」——无点主机名（如 `mybox`）、`.local`
  域名，以及私有网段 IP（`192.168.*`、`10.*`、`172.16-31.*`）。这是把网关跑在 `192.168.x.x:63421` 的关键开关。
- **`NSAllowsArbitraryLoads = false`**：不整体关闭 ATS，公网仍然是 HTTPS 强制，减少 App 审核风险。
- **`localhost` 例外**：仅用于模拟器/本机自测（`http://localhost:63421`）。
- **`NSLocalNetworkUsageDescription`**：iOS 14+ 首次连接局域网会弹「本地网络」权限，用户拒绝后所有端点都会连不上；
  此时去 iPhone「设置 → 隐私与安全性 → 本地网络」重新打开本 App 的开关。
- 如果你的网关用**主机名**（例如 `nas.home:63421`）且不是 `.local`，需要在 `NSExceptionDomains` 里追加该域名并设
  `NSExceptionAllowsInsecureHTTPLoads = true`（ATS 的域名例外不支持写 IP 地址）。
- 若仍然被拦截，排查顺序：① 确认地址是私有网段 IP（`192.168.` / `10.` / `172.16-31.`）而不是公网域名；
  ② 确认 iPhone 已允许「本地网络」权限；③ 实在需要时，仅在开发调试阶段把 `NSAllowsArbitraryLoads` 临时设为 `true`
  （提交 App Store 会被额外审核，不建议上线保留）；④ 最稳妥是给网关配受信任的 TLS 证书走 HTTPS。
- 如果网关开了 TLS（SPEC 2.1 的 `config.tls`），建议用受信任证书；**自签证书**会被 ATS/WKWebView 拒绝，
  需要额外的 `NSExceptionRequiresForwardSecrecy=false` 等放宽项，本项目默认不提供（安全考虑）。
- 网关的 `dshm_device` Cookie 是 HttpOnly，手机端不能靠 JS 设置：WKWebView 在**发起首次请求之前**用
  `WKWebsiteDataStore.httpCookieStore.setCookie(...)` 从原生侧注入；若系统拒绝该 Cookie（个别 IP 域名场景），
  会退回 `document.cookie` 注入脚本。

## 自更新策略（SPEC 第 8 节）

- 桌面端 DSH 更新后，宿主重启，网关随宿主重启，**官方 Web UI 资源仍由宿主提供**。
- iOS 端只是「浏览器 + 原生外壳」：打开或下拉刷新工作台，拿到的就是新版 UI。
  **所以 DSH 官方更新不需要 iOS App 发布新版本。**
- 原生壳自身（SwiftUI 页面、锁屏、配对逻辑）只有在功能变化时才需要重新发版；
  更新页里会一直显示这条说明，避免用户误以为要等 App Store。
- 「更新」页可检查宿主的 `GET /__mobile/api/update`：当前版本 / 官方最新版 / 通道 / 是否可更新；
  网关侧检查失败时它返回 `ok:false` + `error`，App 显示「无法检查更新」而不是报错崩溃。
- App Store 版本检查只是占位：在「设置 → 关于 → App Store ID」填入数字 id 后，更新页会出现跳转商店的按钮。

## 深链配对

```
dshmobile://pair?url=<URL 编码的网关地址>&code=<6 位配对码>[&name=<可选设备名>]
```

例：`dshmobile://pair?url=http%3A%2F%2F192.168.3.18%3A63421&code=123456`

App 内 `onOpenURL` 解析后直接走「配对 → 存 Keychain → 加入端点列表 → 拉一次状态」，并给出成功/失败提示；
`url` 缺失或 `code` 不是 6 位数字时给出明确错误。桌面端「设置 → 移动端」可以把这条链接做成二维码或直接复制。

## 静态自检（Windows 上可跑）

本机没有 Xcode 时，用脚本代替编译验证：

```powershell
# PyYAML 校验 project.yml / workflow，Pillow 校验图标，tree-sitter 做 Swift 语法解析
python -m pip install pyyaml pillow tree_sitter tree_sitter_swift
python ios/scripts/static-check.py
```

检查内容：project.yml 合法 YAML 且 bundle id/版本/Info.plist/scheme/无第三方依赖；
Info.plist plistlib 解析 + ATS/URL scheme/Face ID/局域网用途键；Assets 的 Contents.json 合法且 AppIcon 真实存在；
每个 Swift 文件括号配平、无 TODO/FIXME、无裸 `fatalError`、无 `try!`/`as!`、无 iOS 17 专属 API；
**tree-sitter-swift 语法解析**（装了 `tree_sitter` + `tree_sitter_swift` 时自动启用，报 ERROR/MISSING 节点）；
`t("...")` 用到的文案在 zh-Hans 与 en 中齐全且键集合一致、格式占位符一致；workflow 合法 YAML。
**这不等于编译通过**——类型检查仍需 macOS + Xcode（CI 的 `xcodebuild` 步骤负责这一层）。

## 已知限制

- **Windows 上无法本地编译**：没有 `swiftc`/iOS SDK。本目录只做了静态自检，编译验证在 macOS 14（本地 Xcode 或 GitHub Actions）。
- **WKWebView 的能力边界**：文件下载、跨进程弹窗、部分系统集成（推送、剪贴板高级 API）不如原生 Safari；
  目标链接会转交系统 Safari 打开（`target=_blank` 处理）。终端类功能依赖桌面端 Web UI 自身的能力。
- **后台不轮询**：按 SPEC 要求只在前台轮询（默认 30 秒，可调 10/30/60 秒）；进入后台即停止，返回前台立刻刷新。
- **局域网权限**：用户拒绝「本地网络」权限后无法连接任何端点，需要在系统设置里重新授权。
- **设备令牌撤销**：桌面端撤销设备后，工作台会被网关 302 到配对页，App 会提示「网关要求重新配对」，重新配对即可。
- **同名网关重复配对**：同一网关地址再次配对时只刷新令牌与设备 id，不会重复添加端点。
- **切换语言会重建视图树**：为保证所有文案立即刷新，语言改变时整棵树按 `.id(settings.language)` 重建，
  正在打开的工作台会重新加载一次（等价于刷新，不会丢会话）。
- **AppIcon** 由 `scripts/make-app-icon.py` 生成的 1024×1024 占位图，正式上架请替换为品牌图标。
- **`.xcodeproj` 不入库**：`project.yml` 是唯一来源；新增 Swift 文件后必须重新 `xcodegen generate`（CI 里是自动的）。

## 相关文档

- 仓库根 `docs/SPEC.md`：网关 HTTP 契约（第 2 节）、原生壳要求（第 6 节）、升级策略（第 8 节）
- 网关插件与手机控制台 PWA 在 `packages/dsh-mobile-gateway/`（由其它工作流实现）
