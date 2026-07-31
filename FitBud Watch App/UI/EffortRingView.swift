import SwiftUI

/// The effort ring: a thick arc that drains over the current run/walk interval,
/// with the five-zone scale and a live heart-rate needle outside it.
///
/// Presentation only — every angle comes from `EffortRingGeometry`, which is
/// tested separately.
struct EffortRingView: View {
    let heartRate: Double?
    let currentZone: HRZone?
    /// 1 → 0 across the current run/walk phase. `nil` for unstructured runs,
    /// which draw a full ring in the current zone's colour instead.
    let phaseRemainingFraction: Double?
    /// The zone the session is *meant* to be in, from the plan. Marked on the
    /// scale so target and actual can be compared without reading numbers.
    let targetZoneID: String?

    private var ringColor: Color { currentZone?.color ?? .gray }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let scaleRadius = min(rect.width, rect.height) / 2
            let ringRadius = scaleRadius - Theme.scaleWidth - Theme.ringToScaleGap

            drawZoneScale(in: &context, center: rect.center, radius: scaleRadius)
            drawPhaseRing(in: &context, center: rect.center, radius: ringRadius)
            if let heartRate {
                drawNeedle(in: &context, center: rect.center, radius: scaleRadius, heartRate: heartRate)
            }
        }
    }

    private func drawZoneScale(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for zone in HRZone.table {
            let arc = EffortRingGeometry.arc(for: zone)
            // A hair of padding so adjacent segments read as separate rungs.
            let path = Path { p in
                p.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(arc.start + 1),
                    endAngle: .degrees(arc.end - 1),
                    clockwise: false
                )
            }
            let isActive = zone.id == currentZone?.id
            context.stroke(
                path,
                with: .color(zone.color.opacity(isActive ? 1 : Theme.inactiveZoneOpacity)),
                style: StrokeStyle(lineWidth: Theme.scaleWidth, lineCap: .butt)
            )

            // The target zone gets a thin outline even when the athlete is not
            // in it, so "where I should be" stays visible while drifting.
            if zone.id == targetZoneID, !isActive {
                context.stroke(
                    path,
                    with: .color(zone.color.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .butt)
                )
            }
        }
    }

    private func drawPhaseRing(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let track = Path { p in
            p.addArc(
                center: center, radius: radius,
                startAngle: .degrees(EffortRingGeometry.startAngle),
                endAngle: .degrees(EffortRingGeometry.endAngle),
                clockwise: false
            )
        }
        context.stroke(
            track,
            with: .color(.white.opacity(0.10)),
            style: StrokeStyle(lineWidth: Theme.ringWidth, lineCap: .round)
        )

        let fraction = phaseRemainingFraction ?? 1
        guard fraction > 0 else { return }
        let fill = Path { p in
            p.addArc(
                center: center, radius: radius,
                startAngle: .degrees(EffortRingGeometry.startAngle),
                endAngle: .degrees(EffortRingGeometry.startAngle + EffortRingGeometry.sweep * fraction),
                clockwise: false
            )
        }
        context.stroke(
            fill,
            with: .color(ringColor),
            style: StrokeStyle(lineWidth: Theme.ringWidth, lineCap: .round)
        )
    }

    private func drawNeedle(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, heartRate: Double) {
        let angle = Angle.degrees(EffortRingGeometry.angle(forHeartRate: heartRate))
        let outer = center.offset(by: radius + 4, at: angle)
        let inner = center.offset(by: radius - Theme.scaleWidth - 2, at: angle)
        var path = Path()
        path.move(to: inner)
        path.addLine(to: outer)
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension CGPoint {
    func offset(by distance: CGFloat, at angle: Angle) -> CGPoint {
        CGPoint(
            x: x + distance * cos(angle.radians),
            y: y + distance * sin(angle.radians)
        )
    }
}
