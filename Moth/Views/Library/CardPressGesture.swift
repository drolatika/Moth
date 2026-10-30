import SwiftUI
import UIKit

/// A UIKit long press bridged into SwiftUI. It only takes over once the finger has
/// stayed put for `minimumDuration`, so ordinary swipes still reach the scroll views.
/// After it begins it keeps reporting movement, which drives holding and throwing.
struct CardPressGesture: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.2
    var onBegan: () -> Void
    var onChanged: (_ translation: CGSize) -> Void
    var onEnded: (_ translation: CGSize, _ velocity: CGSize) -> Void
    var onCancelled: () -> Void

    final class Coordinator {
        var start: CGPoint = .zero
        var last: CGPoint = .zero
        var lastTime: TimeInterval = 0
        var velocity: CGSize = .zero
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let state = context.coordinator
        let point = recognizer.location(in: nil)
        let now = CACurrentMediaTime()
        switch recognizer.state {
        case .began:
            state.start = point
            state.last = point
            state.lastTime = now
            state.velocity = .zero
            onBegan()
        case .changed:
            let dt = max(now - state.lastTime, 0.001)
            state.velocity = CGSize(width: (point.x - state.last.x) / dt, height: (point.y - state.last.y) / dt)
            state.last = point
            state.lastTime = now
            onChanged(CGSize(width: point.x - state.start.x, height: point.y - state.start.y))
        case .ended:
            onEnded(CGSize(width: point.x - state.start.x, height: point.y - state.start.y), state.velocity)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }
}
