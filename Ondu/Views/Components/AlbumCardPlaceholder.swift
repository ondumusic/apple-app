import SwiftUI

struct AlbumCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(height: 14)
                .frame(maxWidth: 120)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(height: 12)
                .frame(maxWidth: 60)
        }
    }
}
