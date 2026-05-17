import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = OdileViewModel()
    @State private var undoEventMonitor: Any? = nil

    @EnvironmentObject private var appDelegate: AppDelegate
    @ObservedObject private var colorTheme = MusicEDLColorTheme.shared
    @FocusState private var isOffsetFieldFocused: Bool

    var body: some View {
        let _ = colorTheme.refreshToken

        VStack(spacing: 0) {
            toolbar
            Divider().overlay(AppTheme.softBorder)
            table
            Divider().overlay(AppTheme.softBorder)
            footer
        }
        .background(AppTheme.windowGradient.opacity(0.95))
        .foregroundColor(AppTheme.textPrimary)
        .preferredColorScheme(.dark)
        .opacity(appDelegate.isLaunchSplashCompleted ? 1.0 : 0.0)
        .onAppear(perform: viewModel.handleAppear)
        .onDisappear {
            if let m = undoEventMonitor { NSEvent.removeMonitor(m); undoEventMonitor = nil }
        }
        .alert("Select tracks in Protools then click Load", isPresented: $viewModel.showLaunchInstruction) {
            Button("OK", role: .cancel) {}
        }
        .onDeleteCommand(perform: viewModel.deleteSelectedEntries)
        .onMoveCommand(perform: viewModel.moveSelection)
        .sheet(isPresented: $viewModel.showMarkerSettings) {
            MarkersSettingsSheet(
                colorIndex: $viewModel.markerColorIndex,
                rulerName: $viewModel.markerRulerName,
                rulerOptions: viewModel.markerRulerOptions,
                isLoadingRulers: viewModel.isLoadingMarkerRulers,
                onRefreshRulers: viewModel.refreshMarkerRulerOptions,
                onImport: {
                    viewModel.showMarkerSettings = false
                    viewModel.performImportMarkers()
                },
                onCancel: { viewModel.showMarkerSettings = false }
            )
        }
        .sheet(isPresented: $viewModel.showXLSXPreview) {
            XLSXPreviewSheet(
                entries: viewModel.entries,
                sessionName: viewModel.sessionName,
                settings: $viewModel.xlsxSettings,
                onExport: {
                    viewModel.showXLSXPreview = false
                    viewModel.performExportXLSX()
                },
                onCancel: { viewModel.showXLSXPreview = false }
            )
        }
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("LogoGogoLabs")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
                .offset(x: 25, y: -5)
            
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Odile")
                        .font(.custom("Lobster-Regular", size: 48))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(y: 0)

                    Text(appVersionBadge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.accent.opacity(0.82))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .offset(y: -12)
                }

                Text("EDL Maker assistant")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary.opacity(0.85))
                    .offset(y: -4)
            }
            .frame(height: 60, alignment: .center)
            .offset(y: -4)
            
            Spacer()

            HStack(alignment: .center, spacing: 6) {
                toolbarControl(width: 54, help: " ") {
                    Picker("", selection: $viewModel.offsetSign) {
                        Text("+").tag("+")
                        Text("-").tag("-")
                    }
                    .pickerStyle(.segmented)
                }

                toolbarControl(width: 125, help: "Apply a TC offset.") {
                    TextField("00:00:00:00", text: $viewModel.offsetInput)
                        .gogoTimecodeField(font: .system(size: 15, weight: .semibold, design: .monospaced))
                        .help("Offset HH:MM:SS:FF")
                        .focused($isOffsetFieldFocused)
                        .onSubmit {
                            viewModel.reparseWithCurrentOffset(updateStatus: true)
                            viewModel.endTextEditing()
                        }
                        .onChange(of: viewModel.offsetInput) { _ in
                            viewModel.syncOffsetSignFromInputIfNeeded()
                        }
                }
            }

            toolbarButton("Load", systemImage: "arrow.clockwise", help: "Read PT tracks.", tint: AppTheme.buttonLoad, disabled: viewModel.isLoading, action: viewModel.loadEDL)
                .keyboardShortcut("r", modifiers: [.command])
            toolbarButton(viewModel.isImportingMarkers ? "Importing" : "Markers", systemImage: "mappin.and.ellipse", help: "Send markers.", tint: AppTheme.buttonMarkers, disabled: viewModel.entries.isEmpty || viewModel.isImportingMarkers, action: viewModel.openMarkerSettings)
            toolbarButton("Delete", systemImage: "trash", help: "Remove row.", tint: AppTheme.buttonDelete, disabled: viewModel.selectedEntryIDs.isEmpty, action: viewModel.deleteSelectedEntries)
            toolbarButton("Merge", systemImage: "arrow.triangle.merge", help: "Merge rows.", tint: AppTheme.buttonMerge, disabled: viewModel.selectedEntryIDs.count < 2, action: viewModel.mergeSelectedEntries)
            toolbarButton("XLSX", systemImage: "square.and.arrow.down", help: "Export file.", tint: AppTheme.buttonExport, disabled: viewModel.entries.isEmpty, action: { viewModel.showXLSXPreview = true })

            Spacer(minLength: 0)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        width: CGFloat = 96,
        help: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        toolbarControl(width: width, help: help) {
            Button {
                viewModel.endTextEditing()
                action()
            } label: {
                Label(title, systemImage: systemImage)
            }
            .disabled(disabled)
            .buttonStyle(GogoToolbarButtonStyle(tint: tint))
        }
    }

    private func toolbarControl<Control: View>(
        width: CGFloat = 96,
        help: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(spacing: 6) {
            control()
                .frame(width: width, height: 56)

            Text(help)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: width, alignment: .top)
                .frame(minHeight: 24, alignment: .top)
        }
    }

    private var appVersionBadge: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let version = shortVersion?.isEmpty == false ? shortVersion! : (build?.isEmpty == false ? build! : "1.0")
        return "v\(version)"
    }

    private let actionColumnWidth: CGFloat = 42

    private var table: some View {
        GeometryReader { proxy in
            let widths = effectiveColumnWidths(totalWidth: proxy.size.width)
            VStack(spacing: 0) {
                tableHeader(widths: widths)
                Divider().overlay(AppTheme.softBorder)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                            editableRow(entry: entry, index: index, widths: widths)
                        }
                    }
                }
                .background(AppTheme.backgroundBottom)
            }
            .background(AppTheme.backgroundBottom)
        }
    }

    private func tableColumns(widths: [CGFloat]) -> [GridItem] {
        widths.map { GridItem(.fixed($0), spacing: 0, alignment: .leading) }
        + [GridItem(.fixed(actionColumnWidth), spacing: 0, alignment: .center)]
    }

    private let minColumnWidths: [CGFloat] = [40, 320, 110, 110, 100]

    private func effectiveColumnWidths(totalWidth: CGFloat) -> [CGFloat] {
        var widths = viewModel.columnWidths
        let used = widths.reduce(0, +) + actionColumnWidth
        let extra = max(0, totalWidth - used)
        if widths.indices.contains(1) {
            widths[1] += extra
        }
        return widths
    }

    private func tableHeader(widths: [CGFloat]) -> some View {
        LazyVGrid(columns: tableColumns(widths: widths), alignment: .leading, spacing: 0) {
            headerCell("No", colIndex: 0)
            headerCell("Name", colIndex: 1)
            headerCell("In", colIndex: 2)
            headerCell("Out", colIndex: 3)
            headerCell("Duration", colIndex: 4)
            headerCell("", colIndex: 5)
        }
        .frame(minHeight: 38)
        .background(AppTheme.card.opacity(0.92))
    }

    private func editableRow(entry: MusicEDLEntry, index: Int, widths: [CGFloat]) -> some View {
        let isSelected = viewModel.selectedEntryIDs.contains(entry.id)
        return LazyVGrid(columns: tableColumns(widths: widths), alignment: .leading, spacing: 0) {
            eventCell(entry.event)
            editableNameCell(viewModel.binding(for: entry.id, \.clipName))
            editableTimeCell(viewModel.timeBinding(for: entry.id, \.startTime))
            editableTimeCell(viewModel.timeBinding(for: entry.id, \.endTime))
            editableTimeCell(viewModel.binding(for: entry.id, \.duration), color: AppTheme.textSecondary)

            Button {
                viewModel.deleteEntry(entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.danger)
            .frame(maxWidth: .infinity, minHeight: 34)
            .help("Delete this row")
        }
        .frame(minHeight: 42)
        .background(rowBackground(index: index, isSelected: isSelected))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            let modifiers = NSEvent.modifierFlags
            if modifiers.contains(.command) {
                if viewModel.selectedEntryIDs.contains(entry.id) {
                    viewModel.selectedEntryIDs.remove(entry.id)
                } else {
                    viewModel.selectedEntryIDs.insert(entry.id)
                }
            } else if modifiers.contains(.shift), let lastIdx = viewModel.lastClickedIndex {
                let lo = min(lastIdx, index)
                let hi = max(lastIdx, index)
                let ids = viewModel.entries[lo...hi].map(\.id)
                viewModel.selectedEntryIDs = Set(ids)
            } else {
                viewModel.selectedEntryIDs = [entry.id]
            }
            viewModel.lastClickedIndex = index
        })
        .contextMenu {
            Button("Copy In") {
                viewModel.copyToPasteboard(entry.startTime, status: "In copied")
            }
            Button("Copy Out") {
                viewModel.copyToPasteboard(entry.endTime, status: "Out copied")
            }
            Button("Paste to In") {
                viewModel.pasteTimecode(into: entry.id, keyPath: \.startTime)
            }
            Button("Paste to Out") {
                viewModel.pasteTimecode(into: entry.id, keyPath: \.endTime)
            }
            Divider()
            Button("Copy CSV row") {
                viewModel.copyToPasteboard(viewModel.csvRow(entry), status: "CSV row copied")
            }
            Button("Delete row") {
                viewModel.deleteEntry(entry.id)
            }
        }
    }

    private func headerCell(_ title: String, colIndex: Int) -> some View {
        let isDraggable = colIndex < viewModel.columnWidths.count
        let minW = colIndex < minColumnWidths.count ? minColumnWidths[colIndex] : 40
        return Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .overlay(alignment: .trailing) {
                if isDraggable {
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.001))
                            .frame(width: 10)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                                    .onChanged { value in
                                        if viewModel.dragStartWidths[colIndex] == nil {
                                            viewModel.dragStartWidths[colIndex] = viewModel.columnWidths[colIndex]
                                        }
                                        let startW = viewModel.dragStartWidths[colIndex]!
                                        viewModel.columnWidths[colIndex] = max(minW, startW + value.translation.width)
                                    }
                                    .onEnded { _ in
                                        viewModel.dragStartWidths.removeValue(forKey: colIndex)
                                    }
                            )
                        Rectangle()
                            .fill(AppTheme.softBorder)
                            .frame(width: 1, height: 18)
                    }
                }
            }
    }

    private func editableTextCell(
        _ value: Binding<String>,
        color: Color = AppTheme.textPrimary,
        weight: Font.Weight = .regular
    ) -> some View {
        TextField("", text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: weight))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func editableNameCell(_ value: Binding<String>) -> some View {
        NameCellView(value: value)
    }

    private func eventCell(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(AppTheme.textSecondary)
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func editableTimeCell(_ value: Binding<String>, color: Color = AppTheme.textPrimary) -> some View {
        let isValid = value.wrappedValue.isEmpty || MusicEDLParser.isTimecodeSyntaxValid(value.wrappedValue)
        return TextField("", text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(isValid ? color : AppTheme.warning)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(isValid ? Color.clear : AppTheme.warning.opacity(0.12))
    }

    private func rowBackground(index: Int, isSelected: Bool) -> some View {
        ZStack {
            AppTheme.backgroundBottom

            if !index.isMultiple(of: 2) {
                AppTheme.backgroundTop.opacity(0.24)
            }

            if isSelected {
                AppTheme.accent.opacity(0.26)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()

            if viewModel.isLoading || viewModel.isImportingMarkers {
                ProgressView()
                    .scaleEffect(0.65)
            }

            Text(viewModel.statusText)
                .font(.system(size: 12))
                .foregroundColor(
                    (viewModel.isLoading || viewModel.isImportingMarkers) ? AppTheme.accent :
                    !viewModel.isProToolsOnline ? Color.red :
                    AppTheme.textSecondary
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Divider()
                .frame(height: 16)
                .overlay(AppTheme.softBorder)

            stat(title: "Songs", value: "\(viewModel.entries.count)", tint: AppTheme.accent)
            stat(title: "PT Selection", value: viewModel.foundTracks.isEmpty ? "-" : "\(viewModel.foundTracks.count)", tint: AppTheme.success)

            if !viewModel.missingTracks.isEmpty {
                stat(title: "Missing", value: viewModel.missingTracks.joined(separator: ", "), tint: AppTheme.warning)
            }

            if viewModel.mutedRegionCount > 0 {
                stat(title: "Muted ignored", value: "\(viewModel.mutedRegionCount)", tint: AppTheme.danger)
            }

            Spacer()

            if !viewModel.sessionName.isEmpty {
                Text(viewModel.sessionName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
            }

            Button(action: viewModel.clearEDL) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundColor(viewModel.entries.isEmpty && viewModel.rawSessionInfo.isEmpty ? AppTheme.textMuted.opacity(0.55) : AppTheme.textPrimary)
            .disabled(viewModel.entries.isEmpty && viewModel.rawSessionInfo.isEmpty)

            Button(action: viewModel.copyRawSessionInfo) {
                Label("Raw Session Info", systemImage: "doc.plaintext")
            }
            .buttonStyle(.borderless)
            .foregroundColor(viewModel.rawSessionInfo.isEmpty ? AppTheme.textMuted.opacity(0.55) : AppTheme.textPrimary)
            .disabled(viewModel.rawSessionInfo.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(bandBackground(fill: AppTheme.footer, showTopHighlight: true))
    }

    private var toolbarBackground: some View {
        ZStack(alignment: .top) {
            AppTheme.toolbar

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.glassHighlight, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
    }

    private func bandBackground(fill: Color, showTopHighlight: Bool) -> some View {
        ZStack(alignment: .top) {
            fill

            if showTopHighlight {
                Rectangle()
                    .fill(AppTheme.glassHighlight)
                    .frame(height: 1)
            }
        }
    }

    private func stat(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
        }
    }

}

extension View {
    func gogoTextField(font: Font) -> some View {
        self
            .textFieldStyle(.plain)
            .font(font)
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(AppTheme.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }

    func gogoTimecodeField(font: Font) -> some View {
        self
            .textFieldStyle(.plain)
            .font(font)
            .foregroundColor(AppTheme.textPrimary)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(AppTheme.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}
