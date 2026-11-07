import SwiftUI
import UsageCore

@MainActor
struct ProviderSelector: View {
    @Binding var selection: ProviderID
    var providers: [ProviderID] = ProviderID.configurable

    var body: some View {
        HStack(spacing: 4) {
            ForEach(providers, id: \.self) { provider in
                let selected = selection == provider
                Button { selection = provider } label: {
                    HStack(spacing: 8) {
                        ProviderStyle.brandLogo(provider)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text(verbatim: provider.displayName)
                            .font(.callout.weight(selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(selected
                                ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}
