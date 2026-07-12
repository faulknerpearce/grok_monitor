import SwiftUI
import AppKit

struct MenuBarLabelView: View {
    let snapshot: WeeklyUsageSnapshot?
    let isSignedIn: Bool
    let showBar: Bool
    let showCategories: Bool
    let visibleProductIDs: Set<String>

    private var labelID: String {
        let products = visibleProductIDs.sorted().joined(separator: ",")
        let used = snapshot.map { Int($0.usedPercent.rounded()) } ?? -1
        return "\(showBar)-\(showCategories)-\(products)-\(used)-\(isSignedIn)"
    }

    var body: some View {
        Image(nsImage: MenuBarStatusRenderer.image(
            snapshot: snapshot,
            isSignedIn: isSignedIn,
            showBar: showBar,
            showCategories: showCategories,
            visibleProductIDs: visibleProductIDs
        ))
        .renderingMode(.original)
        .id(labelID)
    }
}
