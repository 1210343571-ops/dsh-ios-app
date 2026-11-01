#!/usr/bin/env python3
"""DSH iOS 静态自检（Windows 上无 swiftc，只能做静态校验）。

检查项：
1. project.yml 是合法 YAML，且包含 SPEC 要求的关键字段。
2. Sources/Info.plist 可被 plistlib 解析，关键键存在（ATS / FaceID / URL scheme）。
3. Assets.xcassets 的 Contents.json 全部合法，AppIcon 引用的 PNG 真实存在且是 1024x1024。
4. 每个 .swift 文件：括号配平、无 TODO/FIXME、无裸 fatalError、无 try!/as!。
5. t("...") 引用的 key 在 zh-Hans/en 两份 Localizable.strings 里都存在，且两份 key 集合一致。
6. 引用到的自研类型都有声明（未定义类型检查，Apple SDK 类型走白名单）。
7. 只使用 iOS 16 可用 API（黑名单扫描 iOS 17+ 专属符号）。
8. GitHub Actions workflow 是合法 YAML。
"""

from __future__ import annotations

import json
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
IOS = ROOT.parent if (ROOT.parent / "project.yml").exists() else ROOT
SOURCES = IOS / "Sources"
FAILS: list[str] = []
NOTES: list[str] = []


def fail(message: str) -> None:
    FAILS.append(message)


def ok(message: str) -> None:
    NOTES.append(message)


# ---------------------------------------------------------------- 1. project.yml
try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

if yaml is not None:
    try:
        spec = yaml.safe_load((IOS / "project.yml").read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f"project.yml 不是合法 YAML: {exc}")
        spec = None
    if spec is not None:
        target = (spec.get("targets") or {}).get("DSHMobile")
        if not isinstance(target, dict):
            fail("project.yml 缺少 targets.DSHMobile")
        else:
            settings = (target.get("settings") or {}).get("base") or {}
            expected = {
                "PRODUCT_BUNDLE_IDENTIFIER": "com.deepseek.dshmobile",
                "MARKETING_VERSION": "1.0.0",
                "INFOPLIST_FILE": "Sources/Info.plist",
            }
            for key, value in expected.items():
                if str(settings.get(key)) != value:
                    fail(f"project.yml settings.{key} 期望 {value!r}，实际 {settings.get(key)!r}")
            scheme_names = list((spec.get("schemes") or {}).keys())
            if "DSHMobile" not in scheme_names:
                fail(f"project.yml 缺少 scheme DSHMobile，实际 {scheme_names}")
            deps = target.get("dependencies")
            if deps:
                fail(f"不允许第三方依赖，实际 {deps}")
            ok("project.yml: 合法 YAML，bundle id/版本/Info.plist/scheme 均符合契约")
else:
    fail("环境里没有 PyYAML，无法校验 project.yml")

# --------------------------------------------------------------- 2. Info.plist
try:
    plist = plistlib.loads((SOURCES / "Info.plist").read_bytes())
    ok("Info.plist: plistlib 解析通过")
except Exception as exc:  # noqa: BLE001
    plist = {}
    fail(f"Info.plist 解析失败: {exc}")

if plist:
    ats = plist.get("NSAppTransportSecurity") or {}
    checks = [
        ("CFBundleURLTypes[0].CFBundleURLSchemes 含 dshmobile",
         "dshmobile" in (plist.get("CFBundleURLTypes") or [{}])[0].get("CFBundleURLSchemes", [])),
        ("NSFaceIDUsageDescription 非空", bool(plist.get("NSFaceIDUsageDescription"))),
        ("NSLocalNetworkUsageDescription 非空", bool(plist.get("NSLocalNetworkUsageDescription"))),
        ("NSAppTransportSecurity.NSAllowsLocalNetworking == True",
         ats.get("NSAllowsLocalNetworking") is True),
        ("NSAppTransportSecurity.NSAllowsArbitraryLoads == False",
         ats.get("NSAllowsArbitraryLoads") is False),
        ("CFBundleShortVersionString == $(MARKETING_VERSION)",
         plist.get("CFBundleShortVersionString") == "$(MARKETING_VERSION)"),
        ("CFBundleIdentifier == $(PRODUCT_BUNDLE_IDENTIFIER)",
         plist.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)"),
        ("UILaunchScreen 存在", isinstance(plist.get("UILaunchScreen"), dict)),
        ("ITSAppUsesNonExemptEncryption == False",
         plist.get("ITSAppUsesNonExemptEncryption") is False),
    ]
    for label, passed in checks:
        if passed:
            ok(f"Info.plist: {label}")
        else:
            fail(f"Info.plist: {label} 不满足")

# ------------------------------------------------------------------ 3. Assets
assets = SOURCES / "Resources" / "Assets.xcassets"
if not assets.exists():
    fail("缺少 Resources/Assets.xcassets")
else:
    for contents in assets.rglob("Contents.json"):
        try:
            data = json.loads(contents.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(f"{contents.relative_to(SOURCES)} 不是合法 JSON: {exc}")
            continue
        if contents.name == "Contents.json" and contents.parent.name == "AppIcon.appiconset":
            images = data.get("images") or []
            if not images:
                fail("AppIcon.appiconset 没有任何图标条目")
            for image in images:
                filename = image.get("filename")
                if not filename:
                    fail("AppIcon.appiconset 有条目缺少 filename")
                    continue
                icon_path = contents.parent / filename
                if not icon_path.exists():
                    fail(f"AppIcon.appiconset 引用的 {filename} 不存在")
                    continue
                if icon_path.stat().st_size < 1024:
                    fail(f"AppIcon {filename} 体积过小（{icon_path.stat().st_size} bytes）")
                try:
                    from PIL import Image
                    with Image.open(icon_path) as image_file:
                        size = image_file.size
                    if size != (1024, 1024):
                        fail(f"AppIcon {filename} 尺寸 {size}，应为 (1024, 1024)")
                    else:
                        ok(f"AppIcon: {filename} 存在且为 1024x1024")
                except ImportError:
                    ok(f"AppIcon: {filename} 存在（无 Pillow，未校验尺寸）")
    ok("Assets.xcassets: 全部 Contents.json 为合法 JSON")

# --------------------------------------------------------------- 4/5/6/7 Swift
swift_files = sorted(SOURCES.rglob("*.swift"))
if not swift_files:
    fail("Sources 下没有 Swift 文件")

BANNED = {
    "fatalError(": "禁止裸用 fatalError",
    "try!": "禁止 try!",
    "as!": "禁止强制 as!",
    "TODO": "禁止遗留 TODO",
    "FIXME": "禁止遗留 FIXME",
    "XXX": "禁止遗留 XXX",
}
IOS17_ONLY = {
    "ContentUnavailableView": "iOS 17 专属",
    "@Observable": "iOS 17 Observation（本项目用 ObservableObject）",
    "#Preview": "Xcode 15 宏，稳妥起见不用",
    ".foregroundStyle": "iOS 17 才常用，改用 foregroundColor",
    ".scrollTargetBehavior": "iOS 17 专属",
    ".symbolEffect": "iOS 17 专属",
    ".containerRelativeFrame": "iOS 17 专属",
    "NavigationLink(value:": "取值版导航需 iOS 16+，未使用",
    "StoreKit": "不引入 StoreKit",
    "Alamofire": "禁止第三方依赖",
    "SnapKit": "禁止第三方依赖",
}

TWO_PARAM_ON_CHANGE = re.compile(r"\.onChange\(of:[^)]*\)\s*\{\s*\w+\s*,\s*\w+\s+in")

declared: set[str] = set()
for path in swift_files:
    text = path.read_text(encoding="utf-8")
    rel = path.relative_to(IOS).as_posix()

    if not text.endswith("\n"):
        fail(f"{rel}: 文件末尾缺少换行")

    for token, reason in BANNED.items():
        for match in re.finditer(re.escape(token), text):
            line = text[: match.start()].count("\n") + 1
            fail(f"{rel}:{line}: 命中禁用模式 {token!r}（{reason}）")

    for token, reason in IOS17_ONLY.items():
        if token in text:
            line = text[: text.index(token)].count("\n") + 1
            fail(f"{rel}:{line}: 命中 {token!r}（{reason}）")

    match = TWO_PARAM_ON_CHANGE.search(text)
    if match:
        line = text[: match.start()].count("\n") + 1
        fail(f"{rel}:{line}: .onChange(of:) 用了 iOS 17 的两参数闭包形式")

    # 括号配平（忽略字符串与注释里的括号）
    stripped = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    stripped = re.sub(r'"(?:\\.|[^"\\])*"', '""', stripped)
    stripped = re.sub(r"//[^\n]*", "", stripped)
    stripped = re.sub(r"/\*(?:.|\n)*?\*/", "", stripped)
    for open_char, close_char in (("{", "}"), ("(", ")"), ("[", "]")):
        if stripped.count(open_char) != stripped.count(close_char):
            fail(f"{rel}: {open_char}{close_char} 不配平 "
                 f"({stripped.count(open_char)} vs {stripped.count(close_char)})")

    # 收集声明
    for match in re.finditer(
        r"\b(?:struct|class|enum|protocol|actor)\s+([A-Z][A-Za-z0-9_]*)", text
    ):
        declared.add(match.group(1))
    for match in re.finditer(r"\btypealias\s+([A-Z][A-Za-z0-9_]*)", text):
        declared.add(match.group(1))

# Apple SDK / 语言内建类型白名单
SDK_TYPES = set(
    """
    Any Bool Character CGFloat CVarArg Data Date Decodable Double Encodable Equatable Error
    Float Formatter Hashable Identifiable Int Int32 Int64 LocalizedError Never NSObject
    NSError NSKeyValueObservation NSURLErrorDomain OSStatus Result Security Sendable
    String Substring TimeInterval UInt UInt64 URL URLComponents URLRequest URLSession
    URLSessionConfiguration URLSessionDataTask URLError UUID UserDefaults Void AnyObject
    Codable CustomStringConvertible Sequence Collection CaseIterable Comparable
    Actor Void DecodingError EncodingError JSONDecoder JSONEncoder JSONSerialization
    ISO8601DateFormatter RelativeDateTimeFormatter DateFormatter DateComponents
    CFDictionary CFTypeRef CFString Array Dictionary Optional Set Range ClosedRange
    NSLock DispatchQueue MainActor Task TaskGroup CheckedContinuation CharacterSet
    CVarArg CustomNSError LocalizedStringKey Mirror Bundle ProcessInfo
    View App Scene WindowGroup Group VStack HStack ZStack List Form Section Text Image
    Button Toggle Picker Menu Label Spacer ProgressView NavigationStack NavigationLink
    NavigationView TabView ScrollView LazyVGrid LazyVStack GridItem ForEach EmptyView
    Alert ConfirmationDialog Bindable Binding ObservedObject StateObject EnvironmentObject
    Environment State Published ObservableObject Color RoundedRectangle Capsule Circle
    Rectangle LinearGradient Material Font EdgeInsets EdgeInsets ColorScheme
    ToolbarItem ToolbarItemGroup ToolbarContentBuilder ToolbarContent LabelStyle
    ProgressViewStyle LinearProgressIndicator ButtonStyle BorderedProminentButtonStyle
    UIViewRepresentable UIView WKWebView WKWebViewConfiguration WKWebsiteDataStore
    WKHTTPCookieStore WKUserScript WKUserContentController WKContentWorld WKNavigation
    WKNavigationDelegate WKNavigationAction WKUIDelegate WKWindowFeatures
    HTTPCookie HTTPCookiePropertyKey UIRefreshControl UIColor UIImage UIApplication
    UIDevice UIPasteboard UIInterfaceOrientation ScenePhase OpenURLAction
    LAContext LAPolicy LAError LABiometryType
    XCTest XCUIApplication
    HTTPURLResponse Logger TextField Content Context NSLocalizedString
    SecItemAdd SecItemDelete SecItemCopyMatching NSPredicate
    """.split()
)

self_declared = declared
unknown: dict[str, set[str]] = {}
for path in swift_files:
    raw_text = path.read_text(encoding="utf-8")
    rel = path.relative_to(IOS).as_posix()
    # 只扫描代码本身，避免字符串/注释里的英文单词被误判成类型。
    text = re.sub(r'"""(?:.|\n)*?"""', '""', raw_text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*(?:.|\n)*?\*/", "", text)
    candidates: set[str] = set()
    # Foo(  Foo.  : Foo  -> Foo
    for pattern in (
        r"(?<![A-Za-z0-9_.])([A-Z][A-Za-z0-9_]{1,40})\s*\(",
        r"(?<![A-Za-z0-9_.])([A-Z][A-Za-z0-9_]{1,40})\s*\.",
        r"[:<]\s*([A-Z][A-Za-z0-9_]{1,40})",
        r"->\s*([A-Z][A-Za-z0-9_]{1,40})",
    ):
        candidates.update(re.findall(pattern, text))
    for candidate in candidates:
        if candidate in self_declared or candidate in SDK_TYPES:
            continue
        if candidate.isupper() and len(candidate) <= 6:  # 常量/环境变量之类
            continue
        unknown.setdefault(candidate, set()).add(rel)
if unknown:
    for name, files in sorted(unknown.items()):
        fail(f"可疑的未声明类型 {name}（出现在 {', '.join(sorted(files))}）")

# 4b. 语法层：tree-sitter-swift（可选，装了就跑；不做类型检查）
try:
    import tree_sitter_swift as tss
    from tree_sitter import Language as TSLanguage
    from tree_sitter import Parser as TSParser
except ImportError:
    NOTES.append("跳过 tree-sitter 语法检查（未安装 tree_sitter / tree_sitter_swift）")
else:
    ts_parser = TSParser(TSLanguage(tss.language()))
    syntax_problems: list[str] = []

    def walk_syntax(node, source: bytes, rel: str) -> None:
        if node.type == "ERROR" or node.is_missing:
            row, column = node.start_point
            syntax_problems.append(f"{rel}:{row + 1}:{column + 1}: {node.type}")
        for child in node.children:
            walk_syntax(child, source, rel)

    for path in swift_files:
        source_bytes = path.read_bytes()
        tree = ts_parser.parse(source_bytes)
        walk_syntax(tree.root_node, source_bytes, path.relative_to(IOS).as_posix())
    if syntax_problems:
        for problem in syntax_problems:
            fail(f"Swift 语法错误 {problem}")
    else:
        ok(f"tree-sitter-swift: {len(swift_files)} 个 Swift 文件语法层解析通过（无 ERROR/MISSING 节点）")

# 5. 本地化 key
used_keys: set[str] = set()
for path in swift_files:
    text = path.read_text(encoding="utf-8")
    used_keys.update(re.findall(r'\bt\("([^"]+)"\)', text))

strings_by_lang: dict[str, dict[str, str]] = {}
for lang in ("zh-Hans", "en"):
    strings_path = SOURCES / "Resources" / f"{lang}.lproj" / "Localizable.strings"
    if not strings_path.exists():
        fail(f"缺少 {strings_path.relative_to(IOS).as_posix()}")
        continue
    parsed: dict[str, str] = {}
    for line_number, raw in enumerate(
        strings_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        match = re.fullmatch(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', line)
        if not match:
            fail(f"{lang}.lproj/Localizable.strings:{line_number}: 语法不合法 -> {line!r}")
            continue
        parsed[match.group(1)] = match.group(2)
    strings_by_lang[lang] = parsed
    ok(f"{lang}.lproj/Localizable.strings: 解析出 {len(parsed)} 条文案")

if len(strings_by_lang) == 2:
    zh_keys, en_keys = set(strings_by_lang["zh-Hans"]), set(strings_by_lang["en"])
    for missing in sorted(used_keys - zh_keys):
        fail(f"Swift 用到但 zh-Hans 缺少文案: {missing}")
    for missing in sorted(used_keys - en_keys):
        fail(f"Swift 用到但 en 缺少文案: {missing}")
    for unused in sorted(zh_keys - used_keys):
        fail(f"{unused} 在 zh-Hans 里定义却没有任何 Swift 代码使用")
    if zh_keys == en_keys and used_keys <= zh_keys:
        ok(f"本地化: {len(used_keys)} 个 key 在 zh-Hans/en 两份文案中齐全")

# 格式串占位符一致性
if len(strings_by_lang) == 2:
    for key in sorted(set(strings_by_lang["zh-Hans"]) & set(strings_by_lang["en"])):
        zh_placeholders = re.findall(r"%[@d%]", strings_by_lang["zh-Hans"][key])
        en_placeholders = re.findall(r"%[@d%]", strings_by_lang["en"][key])
        if zh_placeholders != en_placeholders:
            fail(f"占位符不一致 {key}: zh={zh_placeholders} en={en_placeholders}")

# 8. workflow
workflow = IOS / ".github" / "workflows" / "ios.yml"
if not workflow.exists():
    fail("缺少 .github/workflows/ios.yml")
elif yaml is not None:
    try:
        yaml.safe_load(workflow.read_text(encoding="utf-8"))
        ok(".github/workflows/ios.yml: 合法 YAML")
    except Exception as exc:  # noqa: BLE001
        fail(f".github/workflows/ios.yml 不是合法 YAML: {exc}")

# 9. 其他交付物
for required in ("README.md", ".gitignore", "scripts/generate-project.sh", "project.yml"):
    if not (IOS / required).exists():
        fail(f"缺少 {required}")

# 10. workflow 关键步骤 + README 关键说明
if workflow.exists():
    workflow_text = workflow.read_text(encoding="utf-8")
    for needle in ("macos-14", "xcodegen generate", "iphonesimulator",
                   "CODE_SIGNING_ALLOWED=NO", "secrets.BUILD_CERTIFICATE_BASE64"):
        if needle not in workflow_text:
            fail(f"workflow 缺少关键内容: {needle!r}")
    if not any(token in workflow_text for token in ("archive-skipped", "skipped")):
        fail("workflow 缺少「无签名材料时跳过并说明」的 job")
    if not FAILS or all("workflow" not in problem for problem in FAILS):
        ok("workflow: 包含 macOS 构建 / xcodegen / 模拟器编译 / 可选 archive 步骤")

readme_path = IOS / "README.md"
if readme_path.exists():
    readme = readme_path.read_text(encoding="utf-8")
    for needle in ("xcodegen generate", "xcodebuild", "TestFlight", "NSAllowsLocalNetworking",
                   "自更新", "dshmobile://pair", "已知限制"):
        if needle not in readme:
            fail(f"README 缺少关键说明: {needle!r}")
    for index, line in enumerate(readme.splitlines(), start=1):
        if "\ufffd" in line:
            fail(f"README 第 {index} 行有乱码字符")
    ok("README: 覆盖三种构建方式 / 签名与 TestFlight / ATS / 自更新 / 深链 / 已知限制")

# 11. 文本文件换行符（仓库统一 LF）
for path in [IOS / "README.md", IOS / ".gitignore", workflow,
             IOS / "scripts" / "generate-project.sh", IOS / "project.yml",
             IOS / "Sources" / "Info.plist"]:
    if not path.exists():
        continue
    raw = path.read_bytes()
    if b"\r\n" in raw:
        fail(f"{path.relative_to(IOS).as_posix()} 含 CRLF，仓库统一用 LF")
if not any("CRLF" in problem for problem in FAILS):
    ok("换行符: 交付文本文件均为 LF")

print(f"Swift 文件: {len(swift_files)}")
print(f"声明类型: {len(declared)}")
print(f"本地化 key: {len(used_keys)}")
print()
for note in NOTES:
    print(f"  OK   {note}")
if FAILS:
    print()
    for problem in FAILS:
        print(f"  FAIL {problem}")
    print(f"\n{len(FAILS)} 项未通过")
    sys.exit(1)
print("\n全部静态检查通过")
