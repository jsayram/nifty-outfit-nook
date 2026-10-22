import SwiftUI

/// The outline she stands in on the try-on camera: a simple standing figure, head to toe, arms a
/// little away from the body. It's a guide to size and place, not a measurement.
nonisolated struct BodyOutline: Shape {
    func path(in rect: CGRect) -> Path {
        // The figure is 0.42 wide to 1 tall, centred, with a small margin top and bottom.
        let height = rect.height * 0.9
        let width = height * 0.46
        let originX = rect.midX - width / 2
        let originY = rect.minY + rect.height * 0.05
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: originX + width * x, y: originY + height * y)
        }
        var path = Path()
        // Head.
        path.addEllipse(in: CGRect(x: originX + width * 0.38, y: originY, width: width * 0.24, height: height * 0.115))
        // Body: neck, shoulders, arms a little out, hips, legs apart.
        path.move(to: point(0.46, 0.118))
        path.addLine(to: point(0.46, 0.145))
        path.addLine(to: point(0.2, 0.17))
        path.addLine(to: point(0.02, 0.5))
        path.addLine(to: point(0.09, 0.52))
        path.addLine(to: point(0.26, 0.31))
        path.addLine(to: point(0.3, 0.5))
        path.addLine(to: point(0.3, 0.98))
        path.addLine(to: point(0.47, 0.98))
        path.addLine(to: point(0.5, 0.56))
        path.addLine(to: point(0.53, 0.98))
        path.addLine(to: point(0.7, 0.98))
        path.addLine(to: point(0.7, 0.5))
        path.addLine(to: point(0.74, 0.31))
        path.addLine(to: point(0.91, 0.52))
        path.addLine(to: point(0.98, 0.5))
        path.addLine(to: point(0.8, 0.17))
        path.addLine(to: point(0.54, 0.145))
        path.addLine(to: point(0.54, 0.118))
        return path
    }
}
