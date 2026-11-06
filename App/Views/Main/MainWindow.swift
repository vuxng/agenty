import SwiftUI

struct MainWindow: View {
    let model: AppModel

    @AppStorage(SettingsKey.mainPage) private var page = AppPage.usage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch page {
            case .usage: Text(AppPage.usage.title)
            case .instructions: Text(AppPage.instructions.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AmbientField(page: page, selected: model.selectedInstructions)
                .ignoresSafeArea()
        }
        .frame(minWidth: 860, minHeight: 580)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 2) {
                    ForEach(AppPage.allCases) { item in
                        Button { page = item } label: {
                            Text(item.title)
                                .font(.callout.weight(page == item ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(page == item ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .capsule)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                }
            }
            if page == .usage {
                ToolbarItem(placement: .primaryAction) {
                    Group {
                        if let last = model.store.lastRefreshAt {
                            Text("Updated \(last, format: .dateTime.hour().minute())")
                        } else {
                            Text("Updated —")
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.store.refreshAll(force: true) }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: page)
        .animation(reduceMotion ? nil : .smooth, value: model.selectedInstructions)
        .onAppear { DockPolicy.windowDidAppear() }
        .onDisappear { DockPolicy.windowDidDisappear() }
    }
}
