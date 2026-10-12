import Foundation
import CoreGraphics

/// User-configured multipliers for the Naga's scroll wheel output.
/// Vertical scales wheel ticks and synthetic vertical scroll, horizontal
/// scales tilt (side scroll). These settings apply only in software.
struct ScrollSensitivity: Equatable {
    var vertical: Double
    var horizontal: Double

    static let baseline = ScrollSensitivity(vertical: 1, horizontal: 1)
    static let range: ClosedRange<Double> = 0.1...5
    static let verticalKey = "scrollSensitivityVertical"
    static let horizontalKey = "scrollSensitivityHorizontal"

    func clamped() -> ScrollSensitivity {
        ScrollSensitivity(vertical: Self.clamp(vertical), horizontal: Self.clamp(horizontal))
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 1
    }
}

/// Applies the multipliers to continuous wheel deltas and keeps the fractional
/// remainder of each axis, so 0.3x still emits one line every few ticks
/// instead of rounding every tick down to zero.
final class ScrollScaler {
    private var verticalResidual = 0.0
    private var horizontalResidual = 0.0
    private let lock = NSLock()
    private var previousSensitivity: ScrollSensitivity?

    func apply(vertical: Int64, horizontal: Int64, sensitivity: ScrollSensitivity) -> (vertical: Int64, horizontal: Int64) {
        lock.lock(); defer { lock.unlock() }
        let sensitivity = sensitivity.clamped()
        if previousSensitivity != sensitivity {
            verticalResidual = 0
            horizontalResidual = 0
            previousSensitivity = sensitivity
        }
        return (Self.emit(vertical, sensitivity.vertical, &verticalResidual),
                Self.emit(horizontal, sensitivity.horizontal, &horizontalResidual))
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        verticalResidual = 0
        horizontalResidual = 0
        previousSensitivity = nil
    }

    static func emit(_ delta: Int64, _ factor: Double, _ residual: inout Double) -> Int64 {
        guard delta != 0 else { return 0 }
        guard factor != 1 else { residual = 0; return delta }
        // A reverse tick must not spend a remainder collected in the other direction.
        if residual != 0 && (delta > 0) != (residual > 0) { residual = 0 }
        let total = residual + Double(delta) * factor
        if total >= Double(Int64.max) { residual = 0; return .max }
        if total <= Double(Int64.min) { residual = 0; return .min }
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

enum ScrollAxis { case vertical, horizontal }

/// CGEvent has no public device ID. Match a discrete axis event with one recent
/// Naga HID value, consuming that evidence once. Continuous and momentum events
/// are excluded separately so trackpad gestures do not spend mouse evidence.
struct ScrollInputMatcher {
    struct Match {
        var vertical = false
        var horizontalButton: Int?
        var shiftedWheel = false
        var isEmpty: Bool { !vertical && horizontalButton == nil && !shiftedWheel }
    }
    private struct Tick {
        let axis: ScrollAxis
        let button: Int?
        let timestamp: TimeInterval
    }
    var window: TimeInterval = 0.025
    private var ticks: [Tick] = []

    mutating func record(axis: ScrollAxis, button: Int? = nil, timestamp: TimeInterval) {
        ticks.removeAll { timestamp - $0.timestamp > window }
        ticks.append(Tick(axis: axis, button: button, timestamp: timestamp))
        if ticks.count > 128 { ticks.removeFirst(ticks.count - 128) }
    }

    mutating func consume(vertical: Bool, horizontal: Bool, shifted: Bool = false, timestamp: TimeInterval) -> Match {
        ticks.removeAll { timestamp - $0.timestamp > window }
        var result = Match()
        if vertical, consume(axis: .vertical, timestamp: timestamp) != nil { result.vertical = true }
        if horizontal, let tick = consume(axis: .horizontal, timestamp: timestamp) {
            result.horizontalButton = tick.button
        } else if horizontal && !vertical && shifted,
                  consume(axis: .vertical, timestamp: timestamp) != nil {
            // macOS redirects a wheel tick to the horizontal axis while Shift
            // is held. It is scrolling, not a physical tilt button press.
            result.shiftedWheel = true
        }
        return result
    }

    private mutating func consume(axis: ScrollAxis, timestamp: TimeInterval) -> Tick? {
        let candidates = ticks.indices.filter {
            ticks[$0].axis == axis && abs(timestamp - ticks[$0].timestamp) <= window
        }
        guard let index = candidates.min(by: {
            abs(timestamp - ticks[$0].timestamp) < abs(timestamp - ticks[$1].timestamp)
        }) else { return nil }
        return ticks.remove(at: index)
    }

    mutating func reset() { ticks.removeAll() }
}

/// Apps read line, fixed-point, pixel, raw or accelerated deltas. Snapshot all
/// fields before writing: setting the line delta also changes fixed and pixel
/// fields inside Core Graphics. Each integer representation has its own remainder.
final class ScrollEventScaler {
    private struct AxisFields {
        let line: CGEventField
        let fixed: CGEventField
        let point: CGEventField
        let raw: CGEventField
        let accelerated: CGEventField
        var integer: [CGEventField] { [line, fixed, point] }
        var floating: [CGEventField] { [raw, accelerated] }
    }
    private static let verticalFields = AxisFields(line: .scrollWheelEventDeltaAxis1,
        fixed: .scrollWheelEventFixedPtDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1,
        raw: .scrollWheelEventRawDeltaAxis1, accelerated: .scrollWheelEventAcceleratedDeltaAxis1)
    private static let horizontalFields = AxisFields(line: .scrollWheelEventDeltaAxis2,
        fixed: .scrollWheelEventFixedPtDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2,
        raw: .scrollWheelEventRawDeltaAxis2, accelerated: .scrollWheelEventAcceleratedDeltaAxis2)
    private var residuals: [CGEventField: Double] = [:]
    private var previousSensitivity: ScrollSensitivity?

    static func hasMotion(_ event: CGEvent, axis: ScrollAxis) -> Bool {
        let fields = axis == .vertical ? verticalFields : horizontalFields
        return fields.integer.contains { event.getIntegerValueField($0) != 0 }
            || fields.floating.contains { event.getDoubleValueField($0) != 0 }
    }

    static func isDiscreteHardwareEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
            && event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
            && event.getIntegerValueField(.eventSourceUnixProcessID) == 0
    }

    func reset() {
        residuals.removeAll()
        previousSensitivity = nil
    }

    func apply(to event: CGEvent, sensitivity: ScrollSensitivity,
               vertical: Bool = true, horizontal: Bool = true, suppressHorizontal: Bool = false) {
        let sensitivity = sensitivity.clamped()
        if previousSensitivity != sensitivity {
            residuals.removeAll()
            previousSensitivity = sensitivity
        }
        if vertical { scale(event, fields: Self.verticalFields, factor: sensitivity.vertical) }
        if suppressHorizontal {
            scale(event, fields: Self.horizontalFields, factor: 0)
        } else if horizontal { scale(event, fields: Self.horizontalFields, factor: sensitivity.horizontal) }
    }

    private func scale(_ event: CGEvent, fields: AxisFields, factor: Double) {
        guard factor != 1 else { return }
        let integerValues = fields.integer.map { event.getIntegerValueField($0) }
        let floatingValues = fields.floating.map { event.getDoubleValueField($0) }
        for (field, value) in zip(fields.integer, integerValues) {
            var residual = residuals[field, default: 0]
            let delta = factor == 0 ? 0 : ScrollScaler.emit(value, factor, &residual)
            residuals[field] = factor == 0 ? 0 : residual
            event.setIntegerValueField(field, value: delta)
        }
        for (field, value) in zip(fields.floating, floatingValues) {
            event.setDoubleValueField(field, value: value * factor)
        }
    }
}
