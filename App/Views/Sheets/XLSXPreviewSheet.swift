import SwiftUI

struct XLSXPreviewSheet: View {
    let entries: [MusicEDLEntry]
    let sessionName: String
    @Binding var settings: XLSXExportSettings
    let onExport: () -> Void
    let onCancel: () -> Void

    private let colHeaders = ["No", "Name", "In", "Out", "Duration"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.buttonExport)
                Text("XLSX Export")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().overlay(AppTheme.softBorder)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    previewTable
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 20) {
                    Text("Colors")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    colorRow("Header row", binding: $settings.headerFill)
                    colorRow("Rows (even)", binding: $settings.rowFillEven)
                    colorRow("Rows (odd)", binding: $settings.rowFillOdd)
                }
                .frame(width: 200)
            }
            .padding(24)

            Divider().overlay(AppTheme.softBorder)

            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button("Export") { onExport() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(GogoToolbarButtonStyle(tint: AppTheme.buttonExport))
                    .frame(width: 120)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 680, minHeight: 420)
        .background(AppTheme.backgroundBottom)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var previewTable: some View {
        let preview = Array(entries.prefix(6))
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(colHeaders, id: \.self) { h in
                    Text(h)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: h == "Name" ? .leading : .center)
                        .padding(.horizontal, 6)
                        .background(settings.headerFill)
                }
            }
            ForEach(Array(preview.enumerated()), id: \.offset) { i, entry in
                let fill = i.isMultiple(of: 2) ? settings.rowFillEven : settings.rowFillOdd
                HStack(spacing: 0) {
                    previewCell(entry.event, fill: fill, align: .center)
                    previewCell(entry.clipName, fill: fill, align: .leading)
                    previewCell(entry.startTime, fill: fill, align: .center)
                    previewCell(entry.endTime, fill: fill, align: .center)
                    previewCell(entry.duration, fill: fill, align: .center)
                }
            }
            if entries.count > 6 {
                HStack {
                    Text("… \(entries.count - 6) more rows")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Spacer()
                }
                .background(AppTheme.card.opacity(0.5))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(AppTheme.softBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func previewCell(_ value: String, fill: Color, align: Alignment) -> some View {
        Text(value)
            .font(.system(size: 11))
            .foregroundColor(.black.opacity(0.8))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: align)
            .padding(.horizontal, 6)
            .background(fill)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1)
            }
    }

    private func colorRow(_ label: String, binding: Binding<Color>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 40, height: 28)
        }
    }
}
