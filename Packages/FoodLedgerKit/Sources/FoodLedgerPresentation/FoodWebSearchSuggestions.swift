import FoodLedgerApplication
import SwiftUI
import WebKit

/// Provider HTML is visible but never receives the key, script privileges, persistent
/// website storage or permission to load remote resources without a link tap.
@MainActor
public struct FoodWebSearchSuggestions {
    public let html: String
    @Environment(\.openURL) private var openURL
    public init(html: String) { self.html = html }

    public static func document(_ html: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-src 'none'">
        </head><body>\(html)</body></html>
        """
    }

    @MainActor public final class Coordinator: NSObject, WKNavigationDelegate {
        let open: (URL) -> Void
        var loadedHTML: String?
        init(open: @escaping (URL) -> Void) { self.open = open }
        public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, FoodWebLinkPolicy.isAllowed(url) {
                open(url)
            }
            decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
    @MainActor public func makeCoordinator() -> Coordinator { Coordinator { openURL($0) } }
    @MainActor private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = false
        return webView
    }
    @MainActor private func update(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.document(html), baseURL: nil)
    }
}

#if os(iOS)
extension FoodWebSearchSuggestions: UIViewRepresentable {
    public func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    public func updateUIView(_ uiView: WKWebView, context: Context) { update(uiView, context: context) }
}
#elseif os(macOS)
extension FoodWebSearchSuggestions: NSViewRepresentable {
    public func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    public func updateNSView(_ nsView: WKWebView, context: Context) { update(nsView, context: context) }
}
#endif
