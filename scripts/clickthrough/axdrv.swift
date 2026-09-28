import Foundation
import ApplicationServices
import AppKit

// AX driver for the Pi app. Must be launched with Terminal.app as the
// responsible process so it inherits Terminal's Accessibility grant.

func die(_ m: String) -> Never { print("ERR \(m)"); exit(2) }

guard AXIsProcessTrusted() else { die("not AX trusted") }

func piApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.orchestratorai.pi").first
        ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == "Pi" && $0.activationPolicy == .regular }
}

guard let app = piApp() else { die("Pi not running") }

func activate() {
    if !app.isActive {
        app.activate(options: [])
        usleep(700_000)
    }
}

let axApp = AXUIElementCreateApplication(app.processIdentifier)

func attr(_ el: AXUIElement, _ name: String) -> Any? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}
func str(_ el: AXUIElement, _ name: String) -> String? {
    guard let v = attr(el, name) else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}
func windows() -> [AXUIElement] {
    (attr(axApp, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
}
func ident(_ el: AXUIElement) -> String { str(el, "AXIdentifier") ?? "" }
func role(_ el: AXUIElement) -> String { str(el, kAXRoleAttribute as String) ?? "?" }
func title(_ el: AXUIElement) -> String { str(el, kAXTitleAttribute as String) ?? "" }
func desc(_ el: AXUIElement) -> String { str(el, kAXDescriptionAttribute as String) ?? "" }
func value(_ el: AXUIElement) -> String { str(el, kAXValueAttribute as String) ?? "" }

func label(_ el: AXUIElement) -> String {
    let t = title(el); if !t.isEmpty { return t }
    let d = desc(el); if !d.isEmpty { return d }
    return value(el)
}

/// Depth-first walk with a node budget so a huge SwiftUI tree cannot hang us.
func walk(_ el: AXUIElement, _ depth: Int, _ maxDepth: Int, _ budget: inout Int, _ visit: (AXUIElement, Int) -> Bool) {
    if budget <= 0 || depth > maxDepth { return }
    budget -= 1
    if !visit(el, depth) { return }
    for c in children(el) { walk(c, depth + 1, maxDepth, &budget, visit) }
}

func dump(maxDepth: Int, budget: Int) {
    activate()
    var b = budget
    for (i, w) in windows().enumerated() {
        print("== window \(i): \(title(w))")
        walk(w, 0, maxDepth, &b) { el, d in
            let pad = String(repeating: "  ", count: d)
            var line = "\(pad)\(role(el))"
            let id = ident(el); if !id.isEmpty { line += " #\(id)" }
            let l = label(el)
            if !l.isEmpty { line += " \"" + l.replacingOccurrences(of: "\n", with: "⏎").prefix(160) + "\"" }
            print(line)
            return true
        }
    }
}

/// Find the first element matching a predicate anywhere in the app's windows.
func find(maxDepth: Int = 40, budget: Int = 60000, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    var found: AXUIElement?
    var b = budget
    for w in windows() {
        walk(w, 0, maxDepth, &b) { el, _ in
            if found != nil { return false }
            if match(el) { found = el; return false }
            return true
        }
        if found != nil { break }
    }
    return found
}

func byIdent(_ wanted: String) -> AXUIElement? { find { ident($0) == wanted } }

func press(_ el: AXUIElement) -> Bool {
    ensureVisible(el)
    if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { usleep(250_000); return true }
    // Some SwiftUI controls only respond to a synthesized click.
    return clickEl(el)
}

func setValue(_ el: AXUIElement, _ text: String) -> Bool {
    AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFString) == .success
}


func frame(_ el: AXUIElement) -> CGRect? {
    guard let pos = attr(el, kAXPositionAttribute as String), let sz = attr(el, kAXSizeAttribute as String) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(sz as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

func clickAt(_ c: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(80_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(80_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
}

func screenBounds() -> CGRect { CGDisplayBounds(CGMainDisplayID()) }

func scrollWheel(at p: CGPoint, lines: Int32) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    usleep(180_000)
}

/// Bring an element inside the visible screen area.
/// AXScrollToVisible works for the outline rows (NSTableView implements it) but not for
/// the detail pane, which is a SwiftUI ScrollView. Falling back to the scroll wheel has
/// one trap: the wheel is consumed by whatever is under the cursor, and the report card
/// holds its own inner ScrollView across the middle of the pane. So scroll at the pane's
/// right edge, which is always the outer ScrollView.
func ensureVisible(_ el: AXUIElement) {
    AXUIElementPerformAction(el, "AXScrollToVisible" as CFString)
    usleep(200_000)
    let screen = screenBounds()
    let topSafe = screen.minY + 60      // menu bar + window chrome
    let bottomSafe = screen.maxY - 40
    let edge = CGPoint(x: screen.maxX - 25, y: screen.midY)
    var lastY = CGFloat.greatestFiniteMagnitude
    var stalled = 0
    for _ in 0..<60 {
        guard let f = frame(el) else { return }
        if f.minY >= topSafe && f.maxY <= bottomSafe { return }
        if abs(f.minY - lastY) < 1 {
            stalled += 1
            if stalled > 3 { return }   // pane will not move any further
        } else {
            stalled = 0
        }
        lastY = f.minY
        scrollWheel(at: edge, lines: f.maxY > bottomSafe ? -8 : 8)
    }
}

/// Real mouse click on an element's centre, scrolling it on-screen first.
func clickEl(_ el: AXUIElement) -> Bool {
    ensureVisible(el)
    guard let f = frame(el), f.width > 0, f.height > 0 else { return false }
    let screen = screenBounds()
    guard f.midY > screen.minY, f.midY < screen.maxY else { return false }
    clickAt(CGPoint(x: f.midX, y: f.midY))
    return true
}

func typeText(_ text: String) {
    for ch in text.unicodeScalars {
        var u = UniChar(ch.value > 0xFFFF ? 0x3F : UInt16(ch.value))
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
            e.post(tap: .cghidEventTap)
            usleep(9_000)
        }
    }
    usleep(250_000)
}

func rawKey(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    usleep(150_000)
}

func selectAll() { rawKey(0, .maskCommand) }   // cmd-A

func sendKey(_ name: String) {
    switch name {
    case "esc": rawKey(53)
    case "return": rawKey(36)
    case "tab": rawKey(48)
    case "delete": rawKey(51)
    case "cmd-a": selectAll()
    case "space": rawKey(49)
    default: break
    }
}

func findAll(maxDepth: Int = 40, budget: Int = 80000, _ match: (AXUIElement) -> Bool) -> [AXUIElement] {
    var out: [AXUIElement] = []
    var b = budget
    for w in windows() { walk(w, 0, maxDepth, &b) { el, _ in if match(el) { out.append(el) }; return true } }
    return out
}

/// Pick a value from a SwiftUI Picker rendered as an AXPopUpButton.
func chooseOption(_ popup: AXUIElement, _ option: String) -> Bool {
    if AXUIElementPerformAction(popup, kAXPressAction as CFString) != .success {
        _ = clickEl(popup)
    }
    usleep(600_000)
    // The open menu is a child of the popup (or of the app).
    var menu: AXUIElement? = children(popup).first { role($0) == "AXMenu" }
    if menu == nil {
        var b = 40000
        for w in windows() { walk(w, 0, 40, &b) { el, _ in if menu == nil && role(el) == "AXMenu" { menu = el }; return menu == nil } }
    }
    guard let m = menu else { return false }
    for item in children(m) where title(item) == option {
        if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { usleep(300_000); return true }
        if clickEl(item) { usleep(300_000); return true }
    }
    // close the menu so we do not leave the UI stuck
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    return false
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { die("usage: axdrv <dump|find|press|set|text|exists> ...") }

switch cmd {
case "dump":
    dump(maxDepth: Int(args.count > 1 ? args[1] : "40") ?? 40, budget: Int(args.count > 2 ? args[2] : "20000") ?? 20000)
case "exists":
    activate()
    print(byIdent(args[1]) != nil ? "YES" : "NO")
case "press":
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    print(press(el) ? "OK pressed \(args[1])" : "FAIL press \(args[1])")
case "set":
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    print(setValue(el, args[2]) ? "OK set \(args[1])" : "FAIL set \(args[1])")
case "get":
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    print(label(el))
case "ids":
    activate()
    var b = 60000
    var seen = Set<String>()
    for w in windows() {
        walk(w, 0, 40, &b) { el, _ in
            let id = ident(el)
            if !id.isEmpty && seen.insert(id).inserted { print(id + "\t" + role(el) + "\t" + label(el).replacingOccurrences(of: "\n", with: "⏎").prefix(80)) }
            return true
        }
    }
case "text":
    // All static text in the app, for asserting on-screen copy.
    activate()
    var b = 60000
    for w in windows() {
        walk(w, 0, 40, &b) { el, _ in
            if role(el) == "AXStaticText" || role(el) == "AXTextArea" || role(el) == "AXTextField" {
                let l = label(el).trimmingCharacters(in: .whitespacesAndNewlines)
                if !l.isEmpty { print(l.replacingOccurrences(of: "\n", with: "⏎")) }
            }
            return true
        }
    }
case "menu":
    activate()
    guard let bar = attr(axApp, kAXMenuBarAttribute as String) as! AXUIElement? else { die("no menu bar") }
    var b = 4000
    walk(bar, 0, 4, &b) { el, d in
        print(String(repeating: "  ", count: d) + role(el) + " \"" + title(el) + "\"")
        return true
    }
case "click":
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    print(clickEl(el) ? "OK clicked \(args[1])" : "FAIL click \(args[1])")
case "presstitle":
    activate()
    guard let el = findAll(budget: 80000, { (args[1] == "*" || role($0) == args[1]) && label($0).hasPrefix(args[2]) }).first else { die("no element") }
    let ok = AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    print(ok ? "OK pressed" : "FAIL press")
case "valtitle":
    activate()
    guard let el = findAll(budget: 80000, { (args[1] == "*" || role($0) == args[1]) && label($0).hasPrefix(args[2]) }).first else { die("no element") }
    print("title=\(title(el)) | value=\(value(el)) | desc=\(desc(el))")
case "scroll":
    // scroll <lines> [x] [y]   (positive lines = up)
    activate()
    let sb = screenBounds()
    let sx = Double(args.count > 2 ? args[2] : "") ?? (sb.maxX - 25)
    let sy = Double(args.count > 3 ? args[3] : "") ?? sb.midY
    scrollWheel(at: CGPoint(x: sx, y: sy), lines: Int32(args[1]) ?? -3)
    print("OK scroll at \(Int(sx)),\(Int(sy))")
case "ensure":
    activate()
    guard let el = byIdent(args[1]) else { die("no element") }
    ensureVisible(el)
    guard let f = frame(el) else { die("no frame") }
    print("\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
case "val":
    activate()
    guard let el = byIdent(args[1]) else { die("no element") }
    print("title=\(title(el)) | value=\(value(el)) | desc=\(desc(el))")
case "clickidrole":
    // clickidrole <identifier> <role> [nth]
    activate()
    let hits = findAll { ident($0) == args[1] && role($0) == args[2] }
    let n = Int(args.count > 3 ? args[3] : "0") ?? 0
    guard hits.count > n else { die("no element #\(args[1]) role=\(args[2]) nth=\(n) (found \(hits.count))") }
    print(clickEl(hits[n]) ? "OK clicked" : "FAIL")
case "subtree":
    // subtree <identifier> — dump the ancestor row/cell of an element, with frames
    activate()
    guard let el = byIdent(args[1]) else { die("no element") }
    var top = el
    for _ in 0..<4 { if let p = attr(top, kAXParentAttribute as String) as! AXUIElement? { top = p } }
    var b = 4000
    walk(top, 0, 8, &b) { e, d in
        let f = frame(e)
        print(String(repeating: "  ", count: d) + role(e) + " #" + ident(e) + " \"" + label(e).prefix(40) + "\" " + (f.map { "[\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))x\(Int($0.height))]" } ?? "[-]"))
        return true
    }
case "frame":
    activate()
    guard let el = byIdent(args[1]), let f = frame(el) else { die("no element/frame") }
    print("\(f.origin.x),\(f.origin.y) \(f.width)x\(f.height)")
case "focused":
    activate()
    guard let fe = attr(axApp, "AXFocusedUIElement") as! AXUIElement? else { print("none"); exit(0) }
    print(role(fe) + " #" + ident(fe) + " \"" + label(fe) + "\"")
case "type":
    // type <identifier> <text>   — click to focus, select-all, then type text
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    _ = clickEl(el)
    usleep(300_000)
    selectAll()
    typeText(args[2])
    print("OK typed into \(args[1])")
case "typeat":
    // typeat <role> <label> <text>
    activate()
    guard let el = findAll(budget: 80000, { (args[1] == "*" || role($0) == args[1]) && label($0).hasPrefix(args[2]) }).first else { die("no element") }
    _ = clickEl(el)
    usleep(300_000)
    selectAll()
    typeText(args[3])
    print("OK typed")
case "key":
    activate()
    sendKey(args[1])
    print("OK key \(args[1])")
case "hover":
    activate()
    let hr = args[1], hl = args[2]
    guard let el = findAll(budget: 80000, { (hr == "*" || role($0) == hr) && (label($0) == hl || label($0).hasPrefix(hl)) }).first, let f = frame(el) else { die("no element \(hr)/\(hl)") }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: f.midX, y: f.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(500_000)
    print("OK hover \(hl)")
case "clicktitle":
    // clicktitle <role-or-*> <exact-or-prefix label>
    activate()
    let wantRole = args[1], wantLabel = args[2]
    let hits = findAll { (wantRole == "*" || role($0) == wantRole) && (label($0) == wantLabel || label($0).hasPrefix(wantLabel)) }
    guard let el = hits.first else { die("no element role=\(wantRole) label=\(wantLabel)") }
    print(clickEl(el) ? "OK clicked \(wantLabel)" : "FAIL click \(wantLabel)")
case "choose":
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    print(chooseOption(el, args[2]) ? "OK chose \(args[2])" : "FAIL choose \(args[2])")
case "enabled":
    activate()
    guard let el = byIdent(args[1]) else { die("no element #\(args[1])") }
    let e = attr(el, kAXEnabledAttribute as String) as? Bool ?? true
    print(e ? "ENABLED" : "DISABLED")
case "waitid":
    // waitid <identifier> <seconds>
    let deadline = Date().addingTimeInterval(Double(args.count > 2 ? args[2] : "60") ?? 60)
    while Date() < deadline {
        activate()
        if byIdent(args[1]) != nil { print("FOUND \(args[1])"); exit(0) }
        usleep(2_000_000)
    }
    print("NOTFOUND \(args[1])"); exit(1)
case "winsize":
    // winsize <width> <height> — resize the window, so a "usable at 1280x800"
    // claim is a measurement rather than an assertion.
    activate()
    guard let w = windows().first else { die("no window") }
    var pos = CGPoint(x: 40, y: 40)
    var size = CGSize(width: Double(args[1]) ?? 1440, height: Double(args[2]) ?? 900)
    if let v = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
    if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) }
    usleep(800_000)
    guard let f = frame(w) else { die("no frame after resize") }
    print("\(Int(f.width))x\(Int(f.height))")
case "truncated":
    // truncated <identifier> — does this text element's rendered width cut its value off?
    // AX has no "is truncated" flag, so compare the drawn frame against the width the
    // string needs at the element's own font size.
    activate()
    guard let el = byIdent(args[1]), let f = frame(el) else { die("no element/frame #\(args[1])") }
    let s = label(el)
    let font = NSFont.systemFont(ofSize: Double(args.count > 2 ? args[2] : "13") ?? 13)
    let needed = (s as NSString).size(withAttributes: [.font: font]).width
    // Two lines of room counts as room: the rows wrap rather than truncate.
    let lines = max(1.0, (f.height / (font.ascender - font.descender + font.leading)).rounded(.down))
    print("\(needed <= f.width * lines + 1 ? "FITS" : "TRUNCATED")\t\(Int(needed))pt needed\t\(Int(f.width))x\(Int(f.height)) drawn\t\(Int(lines)) line(s)\t\"\(s)\"")
case "windowtitle":
    activate()
    print(windows().map { title($0) }.joined(separator: " | "))
case "roles":
    activate()
    var b = 80000
    var counts: [String: Int] = [:]
    for w in windows() { walk(w, 0, 40, &b) { el, _ in counts[role(el), default: 0] += 1; return true } }
    for (k, v) in counts.sorted(by: { $0.key < $1.key }) { print("\(k)\t\(v)") }
default:
    die("unknown command \(cmd)")
}
