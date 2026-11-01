import SwiftUI
import UIKit
import WebKit

/// 「工作台」Tab：选中一个端点，用 WKWebView 加载网关根路径（= 桌面端完整 Web UI）。
struct WorkspaceTabView: View {

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var endpoints: EndpointStore

    private var selected: Endpoint? {
        if let id = app.workspaceEndpointID, let endpoint = endpoints.endpoint(withID: id) {
            return endpoint
        }
        if endpoints.count == 1 {
            return endpoints.endpoints.first
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selected = selected {
                    WebWorkspaceView(endpoint: selected)
                } else if endpoints.isEmpty {
                    EmptyHint(icon: "desktopcomputer",
                              title: t("workspace.empty.title"),
                              message: t("workspace.empty.message"))
                        .padding()
                } else {
                    endpointChooser
                }
            }
            .navigationTitle(selected?.name ?? t("workspace.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if endpoints.count > 1 {
                        Menu {
                            ForEach(endpoints.endpoints) { endpoint in
                                Button {
                                    app.workspaceEndpointID = endpoint.id
                                } label: {
                                    if endpoint.id == selected?.id {
                                        Label(endpoint.name, systemImage: "checkmark")
                                    } else {
                                        Text(endpoint.name)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel(t("workspace.choose"))
                    }
                }
            }
        }
    }

    private var endpointChooser: some View {
        List(endpoints.endpoints) { endpoint in
            Button {
                app.workspaceEndpointID = endpoint.id
            } label: {
                HStack {
                    Label(endpoint.name, systemImage: "macwindow")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// WKWebView 包裹：加载 `{gateway}/`，加载前注入 `dshm_device` Cookie，
/// 支持下拉刷新、错误重试、崩溃恢复、在 Safari 打开。
struct WebWorkspaceView: View {

    let endpoint: Endpoint

    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL

    @StateObject private var controller = WebController()
    @State private var token: String?

    var body: some View {
        VStack(spacing: 0) {
            if controller.isLoading {
                ProgressView(value: min(max(controller.progress, 0.02), 1.0))
                    .progressViewStyle(.linear)
            }

            ZStack(alignment: .top) {
                WebViewContainer(endpoint: endpoint, token: token, controller: controller)
                    .id(endpoint.id)

                if let errorMessage = controller.errorMessage {
                    errorOverlay(message: errorMessage)
                } else if let notice = controller.notice {
                    noticeBanner(notice)
                }
            }
        }
        .toolbar {
            toolbarContent
        }
        .onAppear {
            token = app.deviceToken(for: endpoint.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                controller.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!controller.canGoBack)
            .accessibilityLabel(t("workspace.back"))

            Button {
                controller.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!controller.canGoForward)
            .accessibilityLabel(t("workspace.forward"))

            Spacer()

            Button {
                controller.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(t("workspace.reload"))

            Button {
                openInSafari()
            } label: {
                Image(systemName: "safari")
            }
            .accessibilityLabel(t("workspace.safari"))
        }
    }

    private func errorOverlay(message: String) -> some View {
        ZStack {
            Color(UIColor.systemBackground)
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button {
                    controller.retry()
                } label: {
                    Label(t("common.retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
            Text(notice)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func openInSafari() {
        guard let url = controller.currentURL ?? endpoint.workspaceURL else { return }
        openURL(url)
    }
}

/// 视图与 WKWebView 之间的桥：进度、导航状态、错误与重试计数器。
final class WebController: ObservableObject {

    @Published var progress: Double = 0
    @Published var isLoading = true
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var reloadCounter = 0

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func reload() {
        errorMessage = nil
        notice = nil
        reloadCounter += 1
    }

    func retry() {
        errorMessage = nil
        notice = nil
        reloadCounter += 1
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        if !loading {
            progress = 1
        }
    }

    func updateProgress(_ value: Double) {
        guard isLoading else { return }
        progress = min(max(value, 0), 1)
    }

    func setError(_ message: String?) {
        errorMessage = message
        if message != nil {
            isLoading = false
        }
    }

    func setNotice(_ message: String?) {
        notice = message
    }

    func syncNavigationState(canGoBack: Bool, canGoForward: Bool, url: URL?) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.currentURL = url
    }
}

struct WebViewContainer: UIViewRepresentable {

    let endpoint: Endpoint
    let token: String?
    @ObservedObject var controller: WebController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator,
                                action: #selector(Coordinator.handleRefreshControl(_:)),
                                for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        controller.attach(webView)
        context.coordinator.startObserving(webView: webView)
        context.coordinator.load(webView: webView,
                                 endpoint: endpoint,
                                 token: token,
                                 reloadCounter: controller.reloadCounter)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(webView: webView,
                                 endpoint: endpoint,
                                 token: token,
                                 reloadCounter: controller.reloadCounter)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        private weak var controller: WebController?
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []
        private var loadedEndpointID = ""
        private var loadedToken: String?
        private var lastReloadCounter = -1

        init(controller: WebController) {
            self.controller = controller
        }

        func startObserving(webView: WKWebView) {
            self.webView = webView
            let progress = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                DispatchQueue.main.async {
                    self?.controller?.updateProgress(value)
                }
            }
            let back = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                self?.refreshNavigationState()
            }
            let forward = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                self?.refreshNavigationState()
            }
            let url = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                self?.refreshNavigationState()
            }
            observations = [progress, back, forward, url]
        }

        private func refreshNavigationState() {
            guard let webView = webView else { return }
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward
            let url = webView.url
            DispatchQueue.main.async { [weak self] in
                self?.controller?.syncNavigationState(canGoBack: canGoBack,
                                                      canGoForward: canGoForward,
                                                      url: url)
            }
        }

        func load(webView: WKWebView, endpoint: Endpoint, token: String?, reloadCounter: Int) {
            if loadedEndpointID != endpoint.id {
                loadedEndpointID = endpoint.id
                loadedToken = token
                lastReloadCounter = reloadCounter
                loadRequest(webView: webView, endpoint: endpoint, token: token)
                return
            }
            // 令牌是异步读出来的：拿到后必须带 Cookie 重新加载一次，否则会停在网关的配对页。
            if (loadedToken ?? "") != (token ?? "") {
                loadedToken = token
                lastReloadCounter = reloadCounter
                loadRequest(webView: webView, endpoint: endpoint, token: token)
                return
            }
            guard reloadCounter != lastReloadCounter else { return }
            lastReloadCounter = reloadCounter
            loadRequest(webView: webView, endpoint: endpoint, token: token)
        }

        private func loadRequest(webView: WKWebView, endpoint: Endpoint, token: String?) {
            guard let baseURL = endpoint.baseURL,
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                controller?.setError(t("workspace.error.invalidURL"))
                return
            }
            components.path = "/"
            // 工作台首次加载带上一次性令牌：网关会校验后 302 到干净 URL 并写入
            // HttpOnly Cookie。这比在 WKWebView 里手工塞 Cookie 更可靠。
            if let token, !token.isEmpty {
                components.queryItems = [URLQueryItem(name: "dshm_token", value: token)]
            }
            guard let url = components.url else {
                controller?.setError(t("workspace.error.invalidURL"))
                return
            }

            controller?.setError(nil)
            controller?.setNotice(nil)
            controller?.setLoading(true)
            controller?.updateProgress(0.05)

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData

            if let token, !token.isEmpty,
               let cookie = WebCookie.makeDeviceCookie(token: token, host: baseURL.host ?? "") {
                // WKWebView 启动前写入 Cookie：HttpOnly 的 dshm_device 只能从原生侧注入。
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    webView.load(request)
                }
            } else {
                if let token, !token.isEmpty {
                    WebCookie.installDeviceCookieScript(token: token, in: webView)
                }
                webView.load(request)
            }
        }

        @objc func handleRefreshControl(_ sender: UIRefreshControl) {
            sender.endRefreshing()
            if let webView = webView, webView.url != nil {
                webView.reload()
            } else {
                controller?.reload()
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            controller?.setLoading(true)
            controller?.setError(nil)
            refreshNavigationState()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            refreshNavigationState()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller?.setLoading(false)
            controller?.setNotice(nil)
            if let url = webView.url, url.path.contains("__mobile/pair") {
                controller?.setNotice(t("workspace.notice.pairing"))
            }
            refreshNavigationState()
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            handle(error: error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handle(error: error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            controller?.setLoading(false)
            controller?.setError(t("workspace.error.crashed"))
        }

        private func handle(error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return
            }
            DSHLog.warning("webview navigation failed: \(nsError.localizedDescription)")
            controller?.setLoading(false)
            controller?.setError(String(format: t("workspace.error.failed"), nsError.localizedDescription))
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            return nil
        }
    }
}

/// `dshm_device` Cookie 注入（原生 CookieStore 优先，IP 域名不被接受时退回 document.cookie 脚本）。
enum WebCookie {

    static let name = "dshm_device"

    static func makeDeviceCookie(token: String, host: String) -> HTTPCookie? {
        guard !host.isEmpty else { return nil }
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: token,
            .domain: host,
            .path: "/",
            .secure: "FALSE",
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 90)
        ]
        return HTTPCookie(properties: properties)
    }

    static func installDeviceCookieScript(token: String, in webView: WKWebView) {
        guard token.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            DSHLog.error("refusing to inject unexpected token characters")
            return
        }
        let source = "document.cookie = '\(name)=\(token); path=/; max-age=7776000; SameSite=Lax';"
        let script = WKUserScript(source: source,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
    }
}
