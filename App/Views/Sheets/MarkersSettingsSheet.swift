import SwiftUI

struct MarkersSettingsSheet: View {
    @Binding var colorIndex: Int
    @Binding var rulerName: String
    let rulerOptions: [String]
    let isLoadingRulers: Bool
    let onRefreshRulers: () -> Void
    let onImport: () -> Void
    let onCancel: () -> Void

    private let markerColors: [Color] = [
        Color(hex: "6F34EE"), Color(hex: "942FDB"), Color(hex: "E465C4"), Color(hex: "F83692"),
        Color(hex: "F71E10"), Color(hex: "FF6E27"), Color(hex: "F8AD18"), Color(hex: "EAE500"),
        Color(hex: "B6E64B"), Color(hex: "4DFF4D"), Color(hex: "4DFFE1"), Color(hex: "4DB8FF"),
        Color(hex: "4D6AFF"), Color.white, Color(hex: "B6B6B6"), Color(hex: "222222")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.buttonMarkers)
                Text("Import Markers to Pro Tools")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().overlay(AppTheme.softBorder)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Marker Color")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(1...8, id: \.self) { i in colorButton(i) }
                        }
                        HStack(spacing: 8) {
                            ForEach(9...16, id: \.self) { i in colorButton(i) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Marker Track")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Button(action: onRefreshRulers) {
                            if isLoadingRulers {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppTheme.textSecondary)
                        .help("Refresh marker tracks from current session")
                    }

                    Picker("", selection: $rulerName) {
                        ForEach(rulerOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260, alignment: .leading)

                    TextField("Markers", text: $rulerName)
                        .gogoTextField(font: .system(size: 13))
                        .frame(maxWidth: 260)
                }
            }
            .padding(24)

            Divider().overlay(AppTheme.softBorder)

            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button("Import to Pro Tools") { onImport() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(GogoToolbarButtonStyle(tint: AppTheme.buttonMarkers))
                    .frame(width: 180)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500)
        .background(AppTheme.backgroundBottom)
        .preferredColorScheme(.dark)
    }

    private func colorButton(_ index: Int) -> some View {
        let color = markerColors[index - 1]
        let isSelected = colorIndex == index
        return Button(action: { colorIndex = index }) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : Color.gray.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                )
                .shadow(color: isSelected ? color.opacity(0.5) : .clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
