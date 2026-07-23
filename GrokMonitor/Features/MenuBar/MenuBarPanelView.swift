import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var auth: AuthSessionService
    @ObservedObject var poller: UsagePoller
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore

    var openPreferences: () -> Void
    var openCharts: () -> Void
    var openSignIn: () -> Void

    /// 0 = current calendar week; negative = past weeks.
    @State private var weekOffset: Int = 0
    @State private var showGeminiPopup = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                if auth.needsSignIn && auth.isSignedIn {
                    sessionExpiredHeader
                } else if auth.isSignedIn, let snapshot = poller.snapshot {
                    usageHeader(snapshot)
                } else if auth.isSignedIn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekly SuperGrok Limit")
                            .font(.system(size: 13, weight: .semibold))
                        Text(poller.isRefreshing ? "Refreshing…" : (poller.lastError ?? "Signed in — waiting for usage data."))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if poller.lastError != nil {
                            Button("Sign In Again…") { openSignIn() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    signedOutHeader
                }

                Divider().padding(.vertical, 6)

                menuActions
            }
            .padding(12)
            .opacity(showGeminiPopup ? 0 : 1)
            .allowsHitTesting(!showGeminiPopup)

            if showGeminiPopup {
                geminiPopupContent
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.15), value: showGeminiPopup)
        .onAppear {
            poller.menuIsOpen = true
            Task { await poller.refreshNow() }
        }
        .onDisappear {
            poller.menuIsOpen = false
        }
    }

    private var sessionExpiredHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly SuperGrok Limit")
                .font(.system(size: 13, weight: .semibold))
            Text(poller.lastError ?? "Session expired. Sign in again to load usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Sign In Again…") { openSignIn() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func usageHeader(_ snapshot: WeeklyUsageSnapshot) -> some View {
        let products = settings.filteredProducts(from: snapshot)
        let week = DailyUsageBuilder.week(
            history: history.recent.reversed(),
            current: snapshot,
            serverDaily: snapshot.dailySeries,
            weekOffset: weekOffset,
            resetsAt: snapshot.resetsAt
        )

        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly SuperGrok Limit")
                .font(.system(size: 13, weight: .semibold))

            Text("\(Int(snapshot.usedPercent.rounded()))% used · \(Int(snapshot.remainingPercent.rounded()))% remaining")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SegmentedUsageBar(products: products, height: 10)

            VStack(spacing: 6) {
                ForEach(products) { product in
                    CategoryRow(product: product)
                }
            }
            .padding(.top, 4)

            if let credits = snapshot.extraCreditsBalance, credits > 0 {
                HStack {
                    Text("Extra Usage Credits")
                    Spacer()
                    Text(credits as NSDecimalNumber, formatter: Self.currencyFormatter)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }

            Divider().padding(.vertical, 2)

            DailyUsageChartView(
                week: week,
                onPreviousWeek: { weekOffset -= 1 },
                onNextWeek: { weekOffset = min(0, weekOffset + 1) },
                canGoNext: weekOffset < 0
            )

            // Full reset datetime only when the chart week does not already caption it
            // (e.g. browsing another calendar week, or resetsAt outside Mon–Sun).
            if let resetsAt = snapshot.resetsAt, week.resetCaption == nil {
                Text("Resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            if let error = poller.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private var signedOutHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly SuperGrok Limit")
                .font(.system(size: 13, weight: .semibold))
            Text("Sign in to load your usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Sign In…") { openSignIn() }
                .keyboardShortcut("s", modifiers: [.command])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuActions: some View {
        VStack(spacing: 2) {
            panelButton("Refresh Now", shortcut: "⌘R") {
                Task { await poller.refreshNow() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Toggle(isOn: $settings.showCategoriesInMenuBar) {
                toggleLabel("Show Categories in Menu Bar", isOn: settings.showCategoriesInMenuBar)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .font(.system(size: 13))

            Toggle(isOn: $settings.showBarGraphInMenuBar) {
                toggleLabel("Show Bar Graph in Menu Bar", isOn: settings.showBarGraphInMenuBar)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .font(.system(size: 13))

            if !auth.isSignedIn {
                panelButton("Sign In…", shortcut: nil, action: openSignIn)
            }

            Divider().padding(.vertical, 4)

            panelButton("Open Grok Monitor…", shortcut: "⌘O", action: openPreferences)
                .keyboardShortcut("o", modifiers: [.command])

            panelButton("Usage History…", shortcut: nil, action: openCharts)

            Divider().padding(.vertical, 4)

            panelButton("Add Gemini", shortcut: nil) {
                showGeminiPopup = true
            }

            Divider().padding(.vertical, 4)

            panelButton("Quit Grok Monitor", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func panelButton(_ title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }

    private func toggleLabel(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private var geminiPopupContent: some View {
        ZStack {
            VStack(spacing: 16) {
                Image(nsImage: Self.noGeminiImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("Use a better model.")
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack {
                HStack {
                    Button {
                        showGeminiPopup = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Prefer the bundled PNG file so MenuBarExtra reliably shows the provided artwork.
    private static let noGeminiImage: NSImage = {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "NoGemini", withExtension: "png"),
           let fromFile = NSImage(contentsOf: url) {
            image = fromFile
        } else if let named = NSImage(named: "NoGemini") {
            image = (named.copy() as? NSImage) ?? named
        } else {
            image = NSImage(size: NSSize(width: 140, height: 140))
        }
        image.isTemplate = false
        return image
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()
}
