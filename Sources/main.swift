import Cocoa
import Sparkle
import WebKit

let defaults = UserDefaults.standard
let draftURL: URL = {
    let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Draftpad")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("draft.md")
}()

let themeGroups = [
    [("auto", "Auto (follow system)")],
    [("vs", "Light"), ("hc-light", "High Contrast Light"), ("solarized-light", "Solarized Light"), ("github-light", "GitHub Light")],
    [("vs-dark", "Dark"), ("hc-black", "High Contrast Dark"), ("solarized-dark", "Solarized Dark"), ("monokai", "Monokai")],
]

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    let root = Bundle.main.resourceURL!.appendingPathComponent("web")
    static let mime = ["html": "text/html", "js": "text/javascript", "css": "text/css", "json": "application/json",
                       "ttf": "font/ttf", "svg": "image/svg+xml", "map": "application/json"]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let rel = String(task.request.url!.path.dropFirst())
        let file = root.appendingPathComponent(rel.isEmpty ? "index.html" : rel)
        guard file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = Self.mime[file.pathExtension] ?? "application/octet-stream"
        let headers = ["Content-Type": type + "; charset=utf-8", "Content-Length": "\(data.count)",
                       "Access-Control-Allow-Origin": "*"]
        task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// Monaco keeps its own undo stack, so route undo/redo to it.
final class EditorWebView: WKWebView {
    @objc func undo(_ sender: Any?) { evaluateJavaScript("draftpad.trigger('undo')") }
    @objc func redo(_ sender: Any?) { evaluateJavaScript("draftpad.trigger('redo')") }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSMenuDelegate, NSMenuItemValidation {
    var window: NSWindow!
    var webView: EditorWebView!
    var text = ""
    var pendingSave: DispatchWorkItem?
    var alwaysOnTopItem: NSMenuItem!
    let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    var fontSize: Int { get { defaults.object(forKey: "fontSize") as? Int ?? 13 } set { defaults.set(newValue, forKey: "fontSize") } }
    var theme: String { get { defaults.string(forKey: "theme") ?? "auto" } set { defaults.set(newValue, forKey: "theme") } }
    var alwaysOnTop: Bool { get { defaults.bool(forKey: "alwaysOnTop") } set { defaults.set(newValue, forKey: "alwaysOnTop") } }

    func applicationDidFinishLaunching(_ note: Notification) {
        // Two instances would clobber each other's draft.md on flush. A relaunch passes the old PID; wait for it to exit.
        if let i = CommandLine.arguments.firstIndex(of: "--wait-pid"), i + 1 < CommandLine.arguments.count,
           let pid = pid_t(CommandLine.arguments[i + 1]) {
            for _ in 0..<50 where kill(pid, 0) == 0 { usleep(100_000) }
        }
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .first(where: { !$0.isTerminated && $0.processIdentifier != NSRunningApplication.current.processIdentifier }) {
            other.activate(options: [])
            NSApp.terminate(nil)  // window is still nil here, so flush() writes nothing
            return
        }
        moveToApplicationsIfNeeded { [self] in launch() }
    }

    func launch() {
        updaterController.startUpdater()
        text = (try? String(contentsOf: draftURL, encoding: .utf8)) ?? ""
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(), forURLScheme: "draftpad")
        config.userContentController.add(self, name: "draftpad")
        webView = EditorWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        injectState()
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Draftpad"
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = alwaysOnTop ? .floating : .normal
        window.center()
        window.setFrameAutosaveName("DraftpadMain")

        buildMenus()
        webView.load(URLRequest(url: URL(string: "draftpad://app/index.html")!))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: persistence

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "text":
            text = body["text"] as? String ?? text
            if pendingSave == nil {
                let work = DispatchWorkItem { [weak self] in self?.flush() }
                pendingSave = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        case "language":
            defaults.set(body["language"] as? String, forKey: "language")
        default: break
        }
    }

    func injectState() {
        let state: [String: Any] = ["text": text, "fontSize": fontSize, "theme": theme, "language": defaults.string(forKey: "language") ?? "markdown"]
        let json = String(data: try! JSONSerialization.data(withJSONObject: state), encoding: .utf8)!
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(source: "window.__draftpad = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        injectState()
        webView.reload()
    }

    func flush() {
        guard window != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        try? Data(text.utf8).write(to: draftURL, options: .atomic)
    }

    func applicationWillTerminate(_ note: Notification) { flush() }
    func applicationDidHide(_ note: Notification) { flush() }

    // MARK: window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        flush()
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ note: Notification) { webView.evaluateJavaScript("window.draftpad && draftpad.focus()") }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    // MARK: menus

    func buildMenus() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu
            items.forEach(menu.addItem)
        }
        func mi(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        add("Draftpad", [
            mi("About Draftpad", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            mi("Check for Updates…", #selector(SPUStandardUpdaterController.checkForUpdates(_:)), target: updaterController),
            mi("Check for Updates Automatically", #selector(toggleAutoUpdate), target: self),
            .separator(),
            mi("Hide Draftpad", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            mi("Quit Draftpad", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("Edit", [
            mi("Undo", Selector(("undo:")), "z"),
            mi("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            mi("Cut", #selector(NSText.cut(_:)), "x"),
            mi("Copy", #selector(NSText.copy(_:)), "c"),
            mi("Paste", #selector(NSText.paste(_:)), "v"),
            mi("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        alwaysOnTopItem = mi("Always on Top", #selector(toggleOnTop), "t", [.command, .shift], target: self)
        alwaysOnTopItem.state = alwaysOnTop ? .on : .off
        add("View", [
            mi("Increase Font", #selector(fontUp), "=", target: self),
            mi("Decrease Font", #selector(fontDown), "-", target: self),
            mi("Reset Font", #selector(fontReset), "0", target: self),
            .separator(),
            themeMenu(),
            .separator(),
            mi("Command Palette", #selector(palette), "p", [.command, .shift], target: self),
            alwaysOnTopItem,
        ])
        add("Window", [
            mi("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            mi("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.last?.submenu
    }

    func themeMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Theme")
        for (n, group) in themeGroups.enumerated() {
            if n > 0 { menu.addItem(.separator()) }
            for (id, name) in group {
                let i = NSMenuItem(title: name, action: #selector(pickTheme(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = id
                menu.addItem(i)
            }
        }
        menu.delegate = self
        item.submenu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for i in menu.items { i.state = (i.representedObject as? String) == theme ? .on : .off }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAutoUpdate) {
            item.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
        }
        return true
    }

    @objc func toggleAutoUpdate() {
        updaterController.updater.automaticallyChecksForUpdates.toggle()
    }

    @objc func pickTheme(_ sender: NSMenuItem) {
        theme = sender.representedObject as! String
        injectState()
        webView.evaluateJavaScript("window.draftpad && draftpad.setTheme(\"\(theme)\")")
    }

    func setFont(_ n: Int) {
        fontSize = min(max(n, 8), 72)
        webView.evaluateJavaScript("draftpad.setFontSize(\(fontSize))")
    }
    @objc func fontUp() { setFont(fontSize + 1) }
    @objc func fontDown() { setFont(fontSize - 1) }
    @objc func fontReset() { setFont(13) }
    @objc func palette() { webView.evaluateJavaScript("draftpad.trigger('editor.action.quickCommand')") }
    @objc func toggleOnTop() {
        alwaysOnTop.toggle()
        alwaysOnTopItem.state = alwaysOnTop ? .on : .off
        window.level = alwaysOnTop ? .floating : .normal
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
