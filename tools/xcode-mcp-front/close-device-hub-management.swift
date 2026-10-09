import ApplicationServices
import Darwin
import Foundation

// Device Hub's selection URL opens both its management window and a compact
// simulator window. Close the management window only after the matching compact
// window exists, so a slow simulator never becomes invisible.

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &result)
    return status == .success ? result : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func title(_ element: AXUIElement) -> String {
    attribute(element, kAXTitleAttribute) as? String ?? ""
}

func role(_ element: AXUIElement) -> String {
    attribute(element, kAXRoleAttribute) as? String ?? ""
}

func description(_ element: AXUIElement) -> String {
    attribute(element, kAXDescriptionAttribute) as? String ?? ""
}

guard CommandLine.arguments.count == 3 else { exit(64) }
let hubPath = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let simulatorName = CommandLine.arguments[2]
let hubExecutable = hubPath.appendingPathComponent("Contents/MacOS/DeviceHub").path
func executablePath(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
}
func toolbarHas(_ window: AXUIElement, _ label: String) -> Bool {
    children(window).filter { role($0) == "AXToolbar" }
        .flatMap { children($0) }
        .contains { description($0) == label }
}

func matchesSimulator(_ window: AXUIElement) -> Bool {
    let windowTitle = title(window)
    return windowTitle == simulatorName || windowTitle.hasPrefix(simulatorName + " – ")
}

for _ in 0..<10 {
    let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let pids = Set(onScreen.compactMap { window -> pid_t? in
        guard window[kCGWindowOwnerName as String] as? String == "Device Hub" else { return nil }
        return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    })
    if let pid = pids.first(where: { executablePath($0) == hubExecutable }) {
        let app = AXUIElementCreateApplication(pid)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if windows.contains(where: { matchesSimulator($0) && toolbarHas($0, "Show in Device Hub") }) {
            for window in windows where matchesSimulator(window) && toolbarHas(window, "Open in New Window") {
                if let close = attribute(window, kAXCloseButtonAttribute) {
                    let status = AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
                    if status != .success {
                        fputs("Device Hub management close failed: \(status.rawValue)\n", stderr)
                        exit(1)
                    }
                }
            }
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.2)
}
