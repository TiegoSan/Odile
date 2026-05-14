import SwiftUI

struct NameCellView: View {
    @Binding var value: String

    var body: some View {
        TextField("", text: $value, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(AppTheme.textPrimary)
            .lineLimit(1...4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }
}
