import CoreGraphics
import Foundation

// A real mouse drag inside the Pane window. It moves your cursor for about five seconds.
// usage: swift tools/drag.swift <fromX> <fromY> <toX> <toY> [option]
// Points are relative to the window's top-left. It refuses to run unless Pane is the
// frontmost window, so a click can never land in another app.
let args = Array(CommandLine.arguments.dropFirst())
let numbers = args.compactMap(Double.init)
guard numbers.count == 4 else { print("usage: drag.swift fromX fromY toX toY [option]"); exit(2) }
let holdOption = args.contains("option")

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let normal = windows.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
guard let front = normal.first, (front[kCGWindowOwnerName as String] as? String) == "Pane",
      let bounds = front[kCGWindowBounds as String] as? [String: Double] else {
    print("REFUSED: Pane is not the frontmost window, so no mouse event was sent")
    exit(1)
}
let originX = bounds["X"] ?? 0, originY = bounds["Y"] ?? 0
let source = CGEventSource(stateID: .hidSystemState)

func post(_ type: CGEventType, _ x: Double, _ y: Double) {
    let event = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: CGPoint(x: originX + x, y: originY + y), mouseButton: .left)
    // Always set the keys explicitly, so Option from an earlier run can never linger.
    event?.flags = holdOption ? .maskAlternate : []
    event?.post(tap: .cghidEventTap)
}

/// Presses or releases the Option key for real, so the keyboard state says Option is held,
/// as it is when a person holds the key during a drag.
func option(_ down: Bool) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: down)
    event?.type = .flagsChanged
    event?.flags = down ? .maskAlternate : []
    event?.post(tap: .cghidEventTap)
}

if holdOption { option(true); usleep(300_000) }
post(.mouseMoved, numbers[0], numbers[1]); usleep(300_000)
post(.leftMouseDown, numbers[0], numbers[1]); usleep(200_000)
for step in 1...40 {
    let t = Double(step) / 40
    post(.leftMouseDragged, numbers[0] + (numbers[2] - numbers[0]) * t, numbers[1] + (numbers[3] - numbers[1]) * t)
    usleep(25_000)
}
usleep(400_000)
post(.leftMouseUp, numbers[2], numbers[3])
usleep(500_000)
if holdOption { option(false) }
print("dragged")
