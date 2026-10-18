import SwiftUI
import WebKit
import SafariServices

/// The pinned llama.cpp UI, served by the same local inference process.
struct ChatWebView: UIViewRepresentable {
    let port: Int
    let apiKey: String
    let dismissKeyboardToken: Int
    @Binding var loading: Bool
    @Binding var failure: String?
    @Binding var externalURL: URL?
    @Binding var exportURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let origin = "http://127.0.0.1:\(port)"
        let literal = { (text: String) -> String in
            String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        }
        // Keep the native key out of URLs, chat exports, and web localStorage.
        let script = """
        (() => {
          const origin = \(literal(origin));
          if (location.origin !== origin) return;
          window.__LLAMAPAD_NATIVE__ = true;
          const key = \(literal(apiKey));
          const fetch = window.fetch.bind(window);
          window.fetch = (input, init) => {
            const url = new URL(input instanceof Request ? input.url : input, location.href);
            if (url.origin !== origin) return fetch(input, init);
            const request = new Request(input, init);
            const headers = new Headers(request.headers);
            headers.set('Authorization', 'Bearer ' + key);
            return fetch(new Request(request, {headers}));
          };
          document.addEventListener('DOMContentLoaded', () => { document.title = 'LlamaPad Chat'; });
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .systemGroupedBackground
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "llama-chat"
        view.load(URLRequest(url: URL(string: origin + "/")!))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.dismissedToken != dismissKeyboardToken {
            context.coordinator.dismissedToken = dismissKeyboardToken
            view.evaluateJavaScript("if (document.activeElement instanceof HTMLElement) document.activeElement.blur();")
            view.endEditing(true)
        }
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var dismissedToken = 0
        var parent: ChatWebView
        private var downloads: [ObjectIdentifier: URL] = [:]
        init(_ parent: ChatWebView) { self.parent = parent }
        func local(_ url: URL) -> Bool { url.scheme == "http" && url.host == "127.0.0.1" && url.port == parent.port }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.shouldPerformDownload && (local(url) || url.scheme == "blob") { decisionHandler(.download); return }
            if local(url) || url.absoluteString == "about:blank" { decisionHandler(.allow) }
            else {
                if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { parent.externalURL = url }
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["https", "http"].contains(url.scheme ?? "") { parent.externalURL = url }
            return nil
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .download)
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
            let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appending(path: URL(fileURLWithPath: suggestedFilename).lastPathComponent)
                downloads[ObjectIdentifier(download)] = target
                completionHandler(target)
            } catch { parent.failure = error.localizedDescription; completionHandler(nil) }
        }
        func downloadDidFinish(_ download: WKDownload) { parent.exportURL = downloads.removeValue(forKey: ObjectIdentifier(download)) }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloads.removeValue(forKey: ObjectIdentifier(download))
            parent.failure = "Could not export: \(error.localizedDescription)"
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.loading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { parent.failure = "Chat could not connect. \(error.localizedDescription)" }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.failure = "Chat closed to free memory. Reload to reopen your saved conversations." }
    }
}

struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct ChatExport: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
