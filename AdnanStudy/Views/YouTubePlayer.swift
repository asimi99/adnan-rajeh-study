import SwiftUI
import WebKit
import Observation

/// Drives the embedded YouTube player: current time, play state and seeking.
@MainActor
@Observable
final class YouTubeController {
    private(set) var current: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var ready = false
    private(set) var failed = false
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var onTime: ((Double, Double) -> Void)?

    func seek(_ t: Double) {
        current = t
        webView?.evaluateJavaScript("seekTo(\(Int(t)))", completionHandler: nil)
    }

    func toggle() {
        webView?.evaluateJavaScript(isPlaying ? "pauseIt()" : "playIt()", completionHandler: nil)
    }

    func pause() {
        webView?.evaluateJavaScript("pauseIt()", completionHandler: nil)
    }

    fileprivate func handle(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready": ready = true
        case "state":
            let s = (body["a"] as? Int) ?? -1
            isPlaying = (s == 1)
        case "time":
            let t = (body["a"] as? Double) ?? 0
            let d = (body["b"] as? Double) ?? 0
            current = t
            if d > 0 { duration = d }
            onTime?(t, duration)
        case "error": failed = true
        default: break
        }
    }
}

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    let start: Double
    let controller: YouTubeController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakHandler(context.coordinator), name: "yt")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        controller.webView = web
        web.loadHTMLString(html, baseURL: URL(string: "https://asimi99.github.io/"))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.evaluateJavaScript("pauseIt()", completionHandler: nil)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
    }

    private var html: String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script>
        var player;
        function post(type,a,b){try{window.webkit.messageHandlers.yt.postMessage({type:type,a:a,b:b})}catch(e){}}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('p',{host:'https://www.youtube-nocookie.com',videoId:'\(videoId)',
            playerVars:{playsinline:1,rel:0,modestbranding:1,origin:'https://asimi99.github.io',widget_referrer:'https://asimi99.github.io/adnan-rajeh-study/',start:\(Int(start)),autoplay:\(start > 0 ? 1 : 0)},
            events:{onReady:function(){post('ready')},onStateChange:function(e){post('state',e.data)},onError:function(e){post('error',e.data)}}});
          setInterval(function(){if(player&&player.getCurrentTime){post('time',player.getCurrentTime(),player.getDuration())}},1000);
        }
        function seekTo(t){if(player&&player.seekTo){player.seekTo(t,true);player.playVideo()}}
        function playIt(){if(player&&player.playVideo)player.playVideo()}
        function pauseIt(){if(player&&player.pauseVideo)player.pauseVideo()}
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let controller: YouTubeController
        init(controller: YouTubeController) { self.controller = controller }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated { controller.handle(body) }
        }
    }

    /// Avoids WKUserContentController keeping the coordinator alive forever.
    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ t: WKScriptMessageHandler) { target = t }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            target?.userContentController(c, didReceive: m)
        }
    }
}
