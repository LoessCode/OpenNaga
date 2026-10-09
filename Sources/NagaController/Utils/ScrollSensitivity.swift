import Foundation

// Issue 7: configurable scroll wheel sensitivity, including tilt.
// The multipliers are software settings applied by the event tap and by
// synthetic scroll output. They never touch the hardware.

/// User-configured multipliers for the Naga's scroll wheel output.
/// Vertical scales wheel ticks and synthetic vertical scroll, horizontal
/// scales tilt (side scroll). Other mice and the trackpad are untouched
/// because their events never correlate with a Naga HID edge.
struct ScrollSensitivity: Equatable {
    var vertical: Double
    var horizontal: Double

    static let baseline = ScrollSensitivity(vertical: 1, horizontal: 1)
    static let range: ClosedRange<Double> = 0.1...5
    static let verticalKey = "scrollSensitivityVertical"
    static let horizontalKey = "scrollSensitivityHorizontal"

    func clamped() -> ScrollSensitivity {
        ScrollSensitivity(vertical: min(max(vertical, Self.range.lowerBound), Self.range.upperBound),
                          horizontal: min(max(horizontal, Self.range.lowerBound), Self.range.upperBound))
    }

    /// Scales one synthetic scroll line count. A nonzero input never becomes
    /// zero, so slow settings still scroll on every press.
    static func scaledLine(_ delta: Int32, factor: Double) -> Int32 {
        guard delta != 0, factor != 1 else { return delta }
        return (delta > 0 ? 1 : -1) * Int32(max(1, (abs(Double(delta)) * factor).rounded()))
    }
}

/// Applies the multipliers to continuous wheel deltas and keeps the fractional
/// remainder of each axis, so 0.3x still emits one line every few ticks
/// instead of rounding every tick down to zero.
final class ScrollScaler {
    private var verticalResidual = 0.0
    private var horizontalResidual = 0.0
    private let lock = NSLock()

    func apply(vertical: Int64, horizontal: Int64, sensitivity: ScrollSensitivity) -> (vertical: Int64, horizontal: Int64) {
        lock.lock(); defer { lock.unlock() }
        return (Self.emit(vertical, sensitivity.vertical, &verticalResidual),
                Self.emit(horizontal, sensitivity.horizontal, &horizontalResidual))
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        verticalResidual = 0
        horizontalResidual = 0
    }

    static func emit(_ delta: Int64, _ factor: Double, _ residual: inout Double) -> Int64 {
        guard delta != 0, factor != 1 else { return delta }
        // A reverse tick must not spend a remainder collected in the other direction.
        if residual != 0 && (delta > 0) != (residual > 0) { residual = 0 }
        let total = residual + Double(delta) * factor
        let nearest = total.rounded()
        // Snap accumulated floating point drift: a total within epsilon of an
        // integer is treated as exact, so long sessions stay on target.
        if abs(total - nearest) < 1e-9 {
            residual = 0
            return Int64(nearest)
        }
        // Truncation toward zero diffuses the rounding error exactly: the
        // emitted average converges on the target rate for every factor.
        let emitted = total.rounded(.towardZero)
        residual = total - emitted
        return Int64(emitted)
    }
}
