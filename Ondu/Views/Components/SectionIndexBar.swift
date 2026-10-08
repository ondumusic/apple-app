import SwiftUI

struct SectionIndexBar: View {
    let letters: [String]

    @State private var activeIndex: Int?

    private static let letterSize: CGFloat = 11

    var body: some View {
        if !letters.isEmpty {
            let totalHeight = Self.letterSize * CGFloat(letters.count)

            VStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 9.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.letterSize)
                }
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let raw = Int(value.location.y / Self.letterSize)
                        let i = Swift.max(0, Swift.min(raw, letters.count - 1))
                        guard i != activeIndex else { return }
                        activeIndex = i
                        Haptics.selection()
                        NotificationCenter.default.post(name: .scrollToSectionLetter, object: letters[i])
                    }
                    .onEnded { _ in
                        activeIndex = nil
                    }
            )
            .frame(width: 16, height: totalHeight)
            .padding(.trailing, 2)
        }
    }
}
