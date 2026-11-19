import AppKit
import CoreGraphics

/// Turns touchpad frames into pointer, click and scroll events, roughly like a Mac trackpad:
/// one finger moves the pointer, pressing the pad clicks (two fingers on it: right click),
/// tapping clicks, two fingers scroll (with momentum).
final class TrackpadEngine {
    private let settings: Settings
    private let source: CGEventSource?

    // Fingers seen in the previous frame, by touch id.
    private var last: [UInt8: (x: Double, y: Double)] = [:]
    private var lastTime: TimeInterval = 0
    private var wasPressed = false
    private var heldButton: CGMouseButton?
    /// After a reset, ignore input until every finger has left the pad.
    private var waitForLift = false

    // One "session" runs from the first finger down to the last finger up.
    private var sessionStart: TimeInterval?
    private var sessionMaxFingers = 0
    private var sessionTravel = 0.0
    private var sessionClicked = false
    private var sessionScrolled = false

    private var scrolling = false
    private var scrollPending = (x: 0.0, y: 0.0)
    private var scrollRemainder = (x: 0.0, y: 0.0)
    private var scrollVelocity = (x: 0.0, y: 0.0) // pixels per second
    private var momentumTimer: Timer?

    private var cursor: CGPoint?
    private var lastClick: (time: TimeInterval, point: CGPoint, button: CGMouseButton, count: Int64)?

    init(settings: Settings) {
        self.settings = settings
        source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
    }

    // MARK: Input

    func process(_ frame: PadFrame) {
        let touches = frame.touches
        if waitForLift {
            if touches.isEmpty && !frame.pressed { waitForLift = false; wasPressed = false }
            return
        }
        let dt = min(max(frame.time - lastTime, 0.001), 0.05)
        lastTime = frame.time

        if sessionStart == nil && !touches.isEmpty {
            stopMomentum()
            sessionStart = frame.time
            sessionMaxFingers = 0
            sessionTravel = 0
            sessionClicked = false
            sessionScrolled = false
        }
        sessionMaxFingers = max(sessionMaxFingers, touches.count)

        var deltas: [(x: Double, y: Double)] = []
        for touch in touches {
            if let previous = last[touch.id] { deltas.append((touch.x - previous.x, touch.y - previous.y)) }
        }
        last = Dictionary(touches.map { ($0.id, (x: $0.x, y: $0.y)) }, uniquingKeysWith: { a, _ in a })
        sessionTravel += deltas.map { hypot($0.x, $0.y) }.max() ?? 0

        // Physical click.
        if frame.pressed && !wasPressed {
            if scrolling { endScroll(withMomentum: false) }
            let button: CGMouseButton = touches.count >= 2 ? .right : .left
            mouseDown(button)
            heldButton = button
            sessionClicked = true
        } else if !frame.pressed && wasPressed, let button = heldButton {
            mouseUp(button)
            heldButton = nil
        }
        wasPressed = frame.pressed

        // Movement.
        if touches.count >= 2 && heldButton == nil {
            if deltas.count >= 2 {
                let dx = deltas.map(\.x).reduce(0, +) / Double(deltas.count)
                let dy = deltas.map(\.y).reduce(0, +) / Double(deltas.count)
                scroll(dx: dx, dy: dy, dt: dt)
            }
        } else {
            if scrolling { endScroll(withMomentum: true) }
            // When clicking with one finger and dragging with another, follow the one that moves.
            if !sessionScrolled, let delta = deltas.max(by: { hypot($0.x, $0.y) < hypot($1.x, $1.y) }) {
                movePointer(dx: delta.x, dy: delta.y, dt: dt)
            }
        }

        if touches.isEmpty, let start = sessionStart {
            if scrolling { endScroll(withMomentum: true) }
            scrollPending = (0, 0)
            let isTap = settings.tapToClick && !sessionClicked && !sessionScrolled
                && frame.time - start < 0.22 && sessionTravel < 60
            if isTap { click(sessionMaxFingers >= 2 ? .right : .left) }
            sessionStart = nil
        }
    }

    /// Releases anything held and drops the current touch; used when the touchpad turns off.
    func reset() {
        if let button = heldButton { mouseUp(button) }
        heldButton = nil
        if scrolling { endScroll(withMomentum: false) }
        stopMomentum()
        last = [:]
        sessionStart = nil
        scrollPending = (0, 0)
        waitForLift = true
    }

    // MARK: Pointer

    private func movePointer(dx: Double, dy: Double, dt: TimeInterval) {
        guard dx != 0 || dy != 0 else { return }
        let speed = hypot(dx, dy) / dt // pad units per second
        let gain = 0.45 * settings.pointerSpeed * (1 + 2 * smoothstep(300, 5000, speed))
        let moveX = dx * gain, moveY = dy * gain

        let actual = currentLocation()
        var from = cursor ?? actual
        if hypot(from.x - actual.x, from.y - actual.y) > 2 { from = actual } // a real mouse moved it
        let to = clampToScreens(CGPoint(x: from.x + moveX, y: from.y + moveY), from: from)
        cursor = to

        let type: CGEventType
        switch heldButton {
        case .left?: type = .leftMouseDragged
        case .right?: type = .rightMouseDragged
        default: type = .mouseMoved
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: to, mouseButton: heldButton ?? .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(moveX.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(moveY.rounded()))
        event.post(tap: .cghidEventTap)
    }

    private func currentLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func clampToScreens(_ point: CGPoint, from: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let screens = ids.map { CGDisplayBounds($0) }
        if screens.contains(where: { $0.contains(point) }) { return point }
        guard let screen = screens.first(where: { $0.contains(from) }) ?? screens.first else { return point }
        return CGPoint(x: min(max(point.x, screen.minX), screen.maxX - 1),
                       y: min(max(point.y, screen.minY), screen.maxY - 1))
    }

    // MARK: Clicks

    private func mouseDown(_ button: CGMouseButton) {
        let point = currentLocation()
        cursor = point
        let now = ProcessInfo.processInfo.systemUptime
        var count: Int64 = 1
        if let previous = lastClick, previous.button == button,
           now - previous.time < NSEvent.doubleClickInterval,
           hypot(point.x - previous.point.x, point.y - previous.point.y) < 6 {
            count = previous.count + 1
        }
        lastClick = (now, point, button, count)
        post(button == .right ? .rightMouseDown : .leftMouseDown, button: button, at: point, clicks: count)
    }

    private func mouseUp(_ button: CGMouseButton) {
        post(button == .right ? .rightMouseUp : .leftMouseUp, button: button,
             at: currentLocation(), clicks: lastClick?.count ?? 1)
    }

    private func click(_ button: CGMouseButton) {
        mouseDown(button)
        mouseUp(button)
    }

    private func post(_ type: CGEventType, button: CGMouseButton, at point: CGPoint, clicks: Int64) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        event.post(tap: .cghidEventTap)
    }

    // MARK: Scrolling

    private func scroll(dx: Double, dy: Double, dt: TimeInterval) {
        if !scrolling {
            // Wait for a little travel so two resting fingers don't scroll.
            scrollPending.x += dx
            scrollPending.y += dy
            guard hypot(scrollPending.x, scrollPending.y) > 25 else { return }
            scrolling = true
            sessionScrolled = true
            scrollRemainder = (0, 0)
            scrollVelocity = (0, 0)
            postScroll(x: 0, y: 0, phase: 1, momentum: 0) // began
        }
        let speed = hypot(dx, dy) / dt
        let gain = 0.4 * settings.scrollSpeed * (1 + smoothstep(500, 6000, speed))
        // Natural: content follows the fingers. Positive wheel values move content down/right.
        let sign = settings.naturalScrolling ? 1.0 : -1.0
        let px = dx * gain * sign, py = dy * gain * sign
        postScroll(x: px, y: py, phase: 2, momentum: 0) // changed
        scrollVelocity.x = 0.7 * scrollVelocity.x + 0.3 * (px / dt)
        scrollVelocity.y = 0.7 * scrollVelocity.y + 0.3 * (py / dt)
    }

    private func endScroll(withMomentum: Bool) {
        guard scrolling else { return }
        scrolling = false
        scrollPending = (0, 0)
        postScroll(x: 0, y: 0, phase: 4, momentum: 0) // ended
        if withMomentum && hypot(scrollVelocity.x, scrollVelocity.y) > 250 { startMomentum() }
    }

    private func startMomentum() {
        var velocity = scrollVelocity
        var first = true
        let tick = 1.0 / 120
        momentumTimer = Timer(timeInterval: tick, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            velocity.x *= 0.95
            velocity.y *= 0.95
            if hypot(velocity.x, velocity.y) < 20 {
                self.stopMomentum()
                return
            }
            self.postScroll(x: velocity.x * tick, y: velocity.y * tick, phase: 0, momentum: first ? 1 : 2)
            first = false
        }
        RunLoop.main.add(momentumTimer!, forMode: .common)
    }

    private func stopMomentum() {
        guard let timer = momentumTimer else { return }
        timer.invalidate()
        momentumTimer = nil
        postScroll(x: 0, y: 0, phase: 0, momentum: 3) // momentum ended
    }

    /// phase: 1 began, 2 changed, 4 ended. momentum: 1 begin, 2 continue, 3 end.
    private func postScroll(x: Double, y: Double, phase: Int64, momentum: Int64) {
        scrollRemainder.x += x
        scrollRemainder.y += y
        let wholeX = scrollRemainder.x.rounded(.towardZero)
        let wholeY = scrollRemainder.y.rounded(.towardZero)
        scrollRemainder.x -= wholeX
        scrollRemainder.y -= wholeY
        if phase == 2 || momentum == 2, wholeX == 0, wholeY == 0 { return }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(wholeY), wheel2: Int32(wholeX), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.post(tap: .cghidEventTap)
    }
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
