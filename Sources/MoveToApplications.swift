import Cocoa

private let suppressedKey = "moveToApplicationsSuppressed"

private func originalURL(of bundleURL: URL) -> URL {
    typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
    typealias CreateOriginal = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
    guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
          let isSym = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
          let createSym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return bundleURL }
    var translocated: DarwinBoolean = false
    guard unsafeBitCast(isSym, to: IsTranslocated.self)(bundleURL as CFURL, &translocated, nil), translocated.boolValue,
          let original = unsafeBitCast(createSym, to: CreateOriginal.self)(bundleURL as CFURL, nil) else { return bundleURL }
    return original.takeRetainedValue() as URL
}

private func showError(_ error: Error) {
    let alert = NSAlert(error: error)
    alert.runModal()
}

func moveToApplicationsIfNeeded(continueLaunch: @escaping () -> Void) {
    let source = originalURL(of: Bundle.main.bundleURL).standardizedFileURL
    let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
    guard !source.path.hasPrefix("/Applications/"), !source.path.hasPrefix(userApps),
          !defaults.bool(forKey: suppressedKey) else { return continueLaunch() }

    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "アプリケーションフォルダに移動しますか？"
    alert.informativeText = "自動アップデートを使うには、アプリケーションフォルダへの移動が必要です。移動すると自動アップデートの確認も有効になります。"
    alert.addButton(withTitle: "移動する")
    alert.addButton(withTitle: "移動しない")
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "今後は確認しない"
    let move = alert.runModal() == .alertFirstButtonReturn
    if !move {
        if alert.suppressionButton?.state == .on { defaults.set(true, forKey: suppressedKey) }
        return continueLaunch()
    }

    let fm = FileManager.default
    let destination: URL
    do {
        if fm.isWritableFile(atPath: "/Applications") {
            destination = URL(fileURLWithPath: "/Applications/Draftpad.app")
        } else {
            let dir = URL(fileURLWithPath: userApps)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            destination = dir.appendingPathComponent("Draftpad.app")
        }
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.bundleURL?.standardizedFileURL == destination }) {
            throw NSError(domain: "Draftpad", code: 1, userInfo: [NSLocalizedDescriptionKey: "移動先の Draftpad が実行中です。終了してからやり直してください。"])
        }
        if fm.fileExists(atPath: destination.path) { try fm.trashItem(at: destination, resultingItemURL: nil) }
        try fm.copyItem(at: source, to: destination)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try xattr.run()
        xattr.waitUntilExit()
        guard xattr.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        try? fm.trashItem(at: source, resultingItemURL: nil)
    } catch {
        showError(error)
        return continueLaunch()
    }

    defaults.set(true, forKey: "SUEnableAutomaticChecks")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
        DispatchQueue.main.async {
            if let error {
                showError(error)
                continueLaunch()
            } else {
                NSApp.terminate(nil)
            }
        }
    }
}
