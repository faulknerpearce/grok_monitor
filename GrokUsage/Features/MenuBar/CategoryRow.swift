import SwiftUI

struct CategoryRow: View {
    let product: ProductUsage

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.product(product.colorToken))
                .frame(width: 8, height: 8)
            Text(product.displayName)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(Int(product.percentOfPool.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
    }
}
