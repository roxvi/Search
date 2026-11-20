import AppKit
import XCTest
@testable import Search

@MainActor
final class FloatGestureTests: XCTestCase {
    private class Gesture: NSEvent {
        var gesturePhase: NSEvent.Phase = []
        var pinch: CGFloat = 0
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        override var phase: NSEvent.Phase { gesturePhase }
        override var momentumPhase: NSEvent.Phase { [] }
        override var magnification: CGFloat { pinch }
        override var isDirectionInvertedFromDevice: Bool { true }
        override var scrollingDeltaX: CGFloat { dx }
        override var scrollingDeltaY: CGFloat { dy }
    }

    private func withControls(_ body: (Float.Controls, NSWindow) throws -> Void) rethrows {
        _ = NSApplication.shared
        let away = Float.benchAway, screens = Float.benchScreens, flicks = Float.flicks
        Float.benchAway = NSPoint(x: -20000, y: -20000)
        Float.benchScreens = [NSRect(x: -20000, y: -20000, width: 1440, height: 900)]
        Float.flicks = false
        let panel = NSPanel(contentRect: NSRect(x: -20000, y: -20000, width: 440, height: 247),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.minSize = NSSize(width: 260, height: 146)
        let controls = Float.Controls(frame: NSRect(origin: .zero, size: panel.frame.size))
        panel.contentView = controls
        defer {
            controls.finishInteraction()
            panel.contentView = nil
            panel.close()
            Float.benchAway = away
            Float.benchScreens = screens
            Float.flicks = flicks
        }
        try body(controls, panel)
    }

    func testSwipeMovesWithoutResizingOrAddingShadow() {
        withControls { controls, panel in
            let original = panel.frame
            let event = Gesture()
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame, original)
            XCTAssertFalse(panel.hasShadow)
            XCTAssertNil(controls.pointerAnchor)
            event.gesturePhase = .changed
            event.dx = 80
            event.dy = -40
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame.size, original.size)
            XCTAssertFalse(panel.hasShadow)
            event.gesturePhase = .ended
            event.dx = 0
            event.dy = 0
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame.width, original.width, accuracy: 0.01)
            XCTAssertEqual(panel.frame.height, original.height, accuracy: 0.01)
            XCTAssertEqual(panel.frame.midX, original.midX + 80, accuracy: 1)
            XCTAssertEqual(panel.frame.midY, original.midY + 40, accuracy: 1)
            XCTAssertFalse(panel.hasShadow)
        }
    }

    func testSwipeReleasesPointerAndKeepsControlsHiddenUntilMovement() throws {
        try withControls { controls, panel in
            // An unshown window around the pointer exercises attachment without
            // moving the user's real cursor or displaying anything.
            Float.benchAway = nil
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: mouse.x - 100, y: mouse.y - 100))
            let event = Gesture()
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            XCTAssertNotNil(controls.pointerAnchor)
            XCTAssertTrue(controls.gestureQuiet)
            XCTAssertFalse(controls.isNear)
            controls.mouseEntered(with: event)
            XCTAssertFalse(controls.isNear, "warping into the picture must not reveal controls")
            event.gesturePhase = .ended
            controls.scrollWheel(with: event)
            XCTAssertNil(controls.pointerAnchor)
            XCTAssertTrue(controls.gestureQuiet)
            XCTAssertFalse(controls.isNear)
            let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            controls.mouseMoved(with: move)
            XCTAssertNil(controls.pointerAnchor)
            XCTAssertFalse(controls.gestureQuiet)
            XCTAssertTrue(controls.isNear)
        }
    }

    func testCornerFlickReleasesPointerEvenIfGlideHasAlreadyStarted() {
        withControls { controls, panel in
            Float.benchAway = nil
            Float.flicks = true
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: mouse.x - 100, y: mouse.y - 100))
            Float.benchScreens = [panel.frame.insetBy(dx: -500, dy: -500)]
            let original = panel.frame
            let event = Gesture()
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            XCTAssertNotNil(controls.pointerAnchor)
            event.gesturePhase = .changed
            event.dx = 130
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame, original)
            XCTAssertNotNil(controls.pointerAnchor)
            event.gesturePhase = .ended
            event.dx = 0
            controls.scrollWheel(with: event)
            XCTAssertNil(controls.pointerAnchor)
            XCTAssertTrue(controls.gestureQuiet)
        }
    }

    func testCancellationAndTeardownReleasePointer() {
        withControls { controls, panel in
            Float.benchAway = nil
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: mouse.x - 100, y: mouse.y - 100))
            let event = Gesture()
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            XCTAssertNotNil(controls.pointerAnchor)
            event.gesturePhase = .cancelled
            controls.scrollWheel(with: event)
            XCTAssertNil(controls.pointerAnchor)
            XCTAssertFalse(controls.gestureQuiet)
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            XCTAssertNotNil(controls.pointerAnchor)
            controls.finishInteraction()
            XCTAssertNil(controls.pointerAnchor)
            XCTAssertFalse(controls.gestureQuiet)
        }
    }

    func testCancelledCornerSwipeDoesNotSnap() {
        withControls { controls, panel in
            Float.flicks = true
            let original = panel.frame
            let event = Gesture()
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            event.gesturePhase = .changed
            event.dx = 60
            controls.scrollWheel(with: event)
            event.gesturePhase = .cancelled
            event.dx = 0
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame, original)
            XCTAssertNil(controls.pointerAnchor)
        }
    }

    func testCornerModeAllowsTinyPositionAdjustments() {
        withControls { controls, panel in
            Float.flicks = true
            let original = panel.frame
            let event = Gesture()
            event.gesturePhase = .began
            controls.scrollWheel(with: event)
            event.gesturePhase = .changed
            event.dx = 3
            event.dy = -2
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame.size, original.size)
            XCTAssertFalse(panel.hasShadow)
            event.gesturePhase = .ended
            event.dx = 0
            event.dy = 0
            controls.scrollWheel(with: event)
            XCTAssertEqual(panel.frame.minX, original.minX + 3, accuracy: 1)
            XCTAssertEqual(panel.frame.minY, original.minY + 2, accuracy: 1)
            XCTAssertEqual(panel.frame.size, original.size)
            XCTAssertTrue(controls.gestureQuiet)
            controls.finishInteraction()
            XCTAssertFalse(controls.gestureQuiet)
        }
    }

    func testPinchBatchesResizesUntilAccumulatedDeltaExceedsTwoPercent() {
        withControls { controls, panel in
            let event = Gesture()
            event.gesturePhase = .began
            event.pinch = 0.01
            controls.magnify(with: event)
            XCTAssertEqual(panel.frame.width, 440)
            XCTAssertTrue(controls.gestureQuiet)
            XCTAssertFalse(controls.isNear)
            event.gesturePhase = .changed
            controls.magnify(with: event)
            XCTAssertEqual(panel.frame.width, 440)
            event.pinch = 0.005
            controls.magnify(with: event)
            XCTAssertEqual(panel.frame.width, 451, accuracy: 1)
            event.gesturePhase = .cancelled
            controls.magnify(with: event)
            XCTAssertFalse(controls.gestureQuiet)
        }
    }

    func testSmallPinchIsFlushedAtEndAndCanShrinkAgain() {
        withControls { controls, panel in
            let event = Gesture()
            event.gesturePhase = .began
            event.pinch = 0.005
            controls.magnify(with: event)
            XCTAssertEqual(panel.frame.width, 440)
            event.gesturePhase = .ended
            event.pinch = 0
            controls.magnify(with: event)
            XCTAssertEqual(panel.frame.width, 442.2, accuracy: 1)
            event.gesturePhase = .began
            event.pinch = -0.1
            controls.magnify(with: event)
            XCTAssertLessThan(panel.frame.width, 440)
            XCTAssertEqual(panel.frame.width / panel.frame.height, 440 / 247, accuracy: 0.01)
        }
    }

    func testPinchFitsHeightOfCurrentScreenAndRespectsMinimum() {
        withControls { controls, panel in
            Float.benchScreens = [NSRect(x: -20000, y: -20000, width: 2000, height: 400)]
            let event = Gesture()
            event.gesturePhase = .began
            event.pinch = 10
            controls.magnify(with: event)
            XCTAssertLessThanOrEqual(panel.frame.height, 340.1)
            event.pinch = -10
            controls.magnify(with: event)
            XCTAssertEqual(panel.frame.width, 260, accuracy: 1)
        }
    }
}
