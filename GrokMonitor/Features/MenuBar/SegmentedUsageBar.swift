import SwiftUI

extension Color {
    static func product(_ token: ProductColor) -> Color {
        let c = token.sRGB
        return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    static let usageRemainingTrack = Color.primary.opacity(0.18)
}

struct SegmentedUsageBar: View {
    let products: [ProductUsage]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            // Fill left→right with used product segments; unfilled track = remaining.
            let usedWidth = products.reduce(0.0) { $0 + max(0, $1.percentOfPool) }
            let clampedUsed = min(100, usedWidth)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.usageRemainingTrack)
                HStack(spacing: 0) {
                    ForEach(products) { product in
                        Rectangle()
                            .fill(Color.product(product.colorToken))
                            .frame(width: width * CGFloat(product.percentOfPool / 100))
                    }
                }
                .frame(width: width * CGFloat(clampedUsed / 100), alignment: .leading)
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}
