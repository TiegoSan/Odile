import SwiftUI

struct MusicEDLColorsView: View {
    @ObservedObject private var colorTheme = MusicEDLColorTheme.shared
    @State private var expandedSections: Set<String> = ["window", "table", "text", "buttons"]

    private let sections: [MusicEDLColorSection] = [
        MusicEDLColorSection(
            id: "window",
            title: "Window",
            keys: [
                .backgroundTop, .backgroundBottom,
                .toolbar, .summary, .footer,
                .card, .cardElevated,
                .fieldBackground, .border, .softBorder, .glassHighlight
            ]
        ),
        MusicEDLColorSection(
            id: "table",
            title: "Table",
            keys: [.tableRowA, .tableRowB, .accent, .warning, .danger, .success]
        ),
        MusicEDLColorSection(
            id: "text",
            title: "Text",
            keys: [.textPrimary, .textSecondary, .textMuted]
        ),
        MusicEDLColorSection(
            id: "buttons",
            title: "Buttons",
            keys: [.buttonLoad, .buttonMarkers, .buttonDelete, .buttonMerge, .buttonExport]
        )
    ]

    var body: some View {
        let _ = colorTheme.refreshToken

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image("LogoGogoLabs")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .shadow(color: AppTheme.accent.opacity(0.38), radius: 12, x: 0, y: 5)

                Text("Colors")
                    .font(.custom("Lobster-Regular", size: 42))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Button("Reset Defaults") {
                    colorTheme.resetDefaults()
                }
                .buttonStyle(GogoToolbarButtonStyle(tint: AppTheme.buttonMerge))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background(AppTheme.windowGradient)
    }

    private func sectionView(_ section: MusicEDLColorSection) -> some View {
        let isExpanded = expandedSections.contains(section.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(section.id)
            } label: {
                HStack {
                    Text(section.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardElevated.opacity(0.78))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(section.keys) { key in
                        MusicEDLColorEditorRow(key: key)
                    }
                }
                .padding(16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(AppTheme.card.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.border, lineWidth: AppTheme.cardBorderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private func toggle(_ id: String) {
        if expandedSections.contains(id) {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }
}

struct MusicEDLColorSection: Identifiable {
    let id: String
    let title: String
    let keys: [MusicEDLColorKey]
}

struct MusicEDLColorEditorRow: View {
    let key: MusicEDLColorKey
    @ObservedObject private var colorTheme = MusicEDLColorTheme.shared

    var body: some View {
        HStack(spacing: 12) {
            Text(key.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

            Text(colorTheme.hexString(for: key))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 76, alignment: .trailing)

            ColorPicker("", selection: colorTheme.binding(for: key), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34, height: 28)

            Button("Reset") {
                colorTheme.resetColor(for: key)
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.softBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
