import SwiftUI

struct PageHeader<Top: View, Trailing: View>: View {
    let title: String
    let path: String
    let revealURL: URL?
    private let top: Top
    private let trailing: Trailing

    init(title: String, path: String, revealURL: URL?,
         @ViewBuilder top: () -> Top, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.path = path
        self.revealURL = revealURL
        self.top = top()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                top
                Text(verbatim: title)
                    .font(.system(size: 52, weight: .thin, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Text(verbatim: path)
                    .font(.caption.monospaced())
                if let revealURL {
                    Button("Show in Finder", systemImage: "folder") {
                        Finder.show(revealURL)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
                trailing
            }
            .foregroundStyle(.secondary)
        }
    }
}
