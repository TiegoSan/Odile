import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @ObservedObject private var colorTheme = MusicEDLColorTheme.shared

    @State private var offsetSign = "+"
    @State private var offsetInput = "00:00:00:00"
    @State private var entries: [MusicEDLEntry] = []
    @State private var statusText = "Ready"
    @State private var sessionName = ""
    @State private var foundTracks: [String] = []
    @State private var missingTracks: [String] = []
    @State private var mutedRegionCount = 0
    @State private var rawSessionInfo = ""
    @State private var isLoading = false
    @State private var isImportingMarkers = false
    @State private var frameRate = 25
    @State private var selectedEntryIDs: Set<MusicEDLEntry.ID> = []
    @State private var lastClickedIndex: Int? = nil
    @State private var undoStack: [[MusicEDLEntry]] = []
    @State private var columnWidths: [CGFloat] = [52, 540, 132, 132, 122]
    @State private var dragStartWidths: [Int: CGFloat] = [:]
    @State private var isProToolsOnline = false
    @State private var showMarkerSettings = false
    @State private var markerColorIndex: Int = 1
    @State private var markerRulerName: String = "Markers"
    @State private var markerRulerOptions: [String] = ["Markers"]
    @State private var isLoadingMarkerRulers = false
    @State private var showXLSXPreview = false
    @State private var xlsxSettings = XLSXExportSettings()
    @State private var undoEventMonitor: Any? = nil
    @State private var showLaunchInstruction = false
    @State private var didShowLaunchInstruction = false
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
        .background(AppTheme.windowGradient)
        .foregroundColor(AppTheme.textPrimary)
        .preferredColorScheme(.dark)
        .onAppear(perform: handleAppear)
        .onDisappear {
            if let m = undoEventMonitor { NSEvent.removeMonitor(m); undoEventMonitor = nil }
        }
        .alert("Select tracks in Protools then click Load", isPresented: $showLaunchInstruction) {
            Button("OK", role: .cancel) {}
        }
        .onDeleteCommand(perform: deleteSelectedEntries)
        .onMoveCommand(perform: moveSelection)
        .sheet(isPresented: $showMarkerSettings) {
            MarkersSettingsSheet(
                colorIndex: $markerColorIndex,
                rulerName: $markerRulerName,
                rulerOptions: markerRulerOptions,
                isLoadingRulers: isLoadingMarkerRulers,
                onRefreshRulers: refreshMarkerRulerOptions,
                onImport: {
                    showMarkerSettings = false
                    performImportMarkers()
                },
                onCancel: { showMarkerSettings = false }
            )
        }
        .sheet(isPresented: $showXLSXPreview) {
            XLSXPreviewSheet(
                entries: entries,
                sessionName: sessionName,
                settings: $xlsxSettings,
                onExport: {
                    showXLSXPreview = false
                    performExportXLSX()
                },
                onCancel: { showXLSXPreview = false }
            )
        }
    }

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("LogoGogoLabs")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)
                .offset(x: 20, y: -10)
            
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Odile")
                        .font(.custom("Lobster-Regular", size: 65))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(y: 0)

                    Text(appVersionBadge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.accent.opacity(0.82))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .offset(y: -18)
                }

                Text("EDL Maker assistant")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary.opacity(0.85))
                    .offset(y: -12)
            }
            .frame(height: 98, alignment: .center)
            .offset(y: -17)
            
            Spacer()

            HStack(alignment: .top, spacing: 6) {
                toolbarControl(width: 54, help: " ") {
                    Picker("", selection: $offsetSign) {
                        Text("+").tag("+")
                        Text("-").tag("-")
                    }
                    .pickerStyle(.segmented)
                }

                toolbarControl(width: 125, help: "Apply a TC offset.") {
                    TextField("00:00:00:00", text: $offsetInput)
                        .gogoTimecodeField(font: .system(size: 15, weight: .semibold, design: .monospaced))
                        .help("Offset HH:MM:SS:FF")
                        .focused($isOffsetFieldFocused)
                        .onSubmit {
                            reparseWithCurrentOffset(updateStatus: true)
                            endTextEditing()
                        }
                        .onChange(of: offsetInput) { _ in
                            syncOffsetSignFromInputIfNeeded()
                        }
                }
            }

            toolbarButton("Load", systemImage: "arrow.clockwise", help: "Read PT tracks.", tint: AppTheme.buttonLoad, disabled: isLoading, action: loadEDL)
                .keyboardShortcut("r", modifiers: [.command])
            toolbarButton(isImportingMarkers ? "Importing" : "Markers", systemImage: "mappin.and.ellipse", help: "Send markers.", tint: AppTheme.buttonMarkers, disabled: entries.isEmpty || isImportingMarkers, action: openMarkerSettings)
            toolbarButton("Delete", systemImage: "trash", help: "Remove row.", tint: AppTheme.buttonDelete, disabled: selectedEntryIDs.isEmpty, action: deleteSelectedEntries)
            toolbarButton("Merge", systemImage: "arrow.triangle.merge", help: "Merge rows.", tint: AppTheme.buttonDelete, disabled: selectedEntryIDs.count < 2, action: mergeSelectedEntries)
            toolbarButton("XLSX", systemImage: "square.and.arrow.down", help: "Export file.", tint: AppTheme.buttonExport, disabled: entries.isEmpty, action: { showXLSXPreview = true })

            Spacer(minLength: 0)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                endTextEditing()
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
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
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
        var widths = columnWidths
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
        let isSelected = selectedEntryIDs.contains(entry.id)
        return LazyVGrid(columns: tableColumns(widths: widths), alignment: .leading, spacing: 0) {
            eventCell(entry.event)
            editableNameCell(binding(for: entry.id, \.clipName))
            editableTimeCell(timeBinding(for: entry.id, \.startTime))
            editableTimeCell(timeBinding(for: entry.id, \.endTime))
            editableTimeCell(binding(for: entry.id, \.duration), color: AppTheme.textSecondary)

            Button {
                deleteEntry(entry.id)
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
                if selectedEntryIDs.contains(entry.id) {
                    selectedEntryIDs.remove(entry.id)
                } else {
                    selectedEntryIDs.insert(entry.id)
                }
            } else if modifiers.contains(.shift), let lastIdx = lastClickedIndex {
                let lo = min(lastIdx, index)
                let hi = max(lastIdx, index)
                let ids = entries[lo...hi].map(\.id)
                selectedEntryIDs = Set(ids)
            } else {
                selectedEntryIDs = [entry.id]
            }
            lastClickedIndex = index
        })
        .contextMenu {
            Button("Copy In") {
                copyToPasteboard(entry.startTime, status: "In copied")
            }
            Button("Copy Out") {
                copyToPasteboard(entry.endTime, status: "Out copied")
            }
            Button("Paste to In") {
                pasteTimecode(into: entry.id, keyPath: \.startTime)
            }
            Button("Paste to Out") {
                pasteTimecode(into: entry.id, keyPath: \.endTime)
            }
            Divider()
            Button("Copy CSV row") {
                copyToPasteboard(csvRow(entry), status: "CSV row copied")
            }
            Button("Delete row") {
                deleteEntry(entry.id)
            }
        }
    }

    private func headerCell(_ title: String, colIndex: Int) -> some View {
        let isDraggable = colIndex < columnWidths.count
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
                                        if dragStartWidths[colIndex] == nil {
                                            dragStartWidths[colIndex] = columnWidths[colIndex]
                                        }
                                        let startW = dragStartWidths[colIndex]!
                                        columnWidths[colIndex] = max(minW, startW + value.translation.width)
                                    }
                                    .onEnded { _ in
                                        dragStartWidths.removeValue(forKey: colIndex)
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
            if isLoading || isImportingMarkers {
                ProgressView()
                    .scaleEffect(0.65)
            }

            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(
                    (isLoading || isImportingMarkers) ? AppTheme.accent :
                    !isProToolsOnline ? Color.red :
                    AppTheme.textSecondary
                )
                .lineLimit(1)

            Divider()
                .frame(height: 16)
                .overlay(AppTheme.softBorder)

            stat(title: "Songs", value: "\(entries.count)", tint: AppTheme.accent)
            stat(title: "PT Selection", value: foundTracks.isEmpty ? "-" : "\(foundTracks.count)", tint: AppTheme.success)

            if !missingTracks.isEmpty {
                stat(title: "Missing", value: missingTracks.joined(separator: ", "), tint: AppTheme.warning)
            }

            if mutedRegionCount > 0 {
                stat(title: "Muted ignored", value: "\(mutedRegionCount)", tint: AppTheme.danger)
            }

            Spacer()

            if !sessionName.isEmpty {
                Text(sessionName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
            }

            Button(action: clearEDL) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundColor(entries.isEmpty && rawSessionInfo.isEmpty ? AppTheme.textMuted.opacity(0.55) : AppTheme.textPrimary)
            .disabled(entries.isEmpty && rawSessionInfo.isEmpty)

            Button(action: copyRawSessionInfo) {
                Label("Raw Session Info", systemImage: "doc.plaintext")
            }
            .buttonStyle(.borderless)
            .foregroundColor(rawSessionInfo.isEmpty ? AppTheme.textMuted.opacity(0.55) : AppTheme.textPrimary)
            .disabled(rawSessionInfo.isEmpty)
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

    private func handleAppear() {
        checkHost()
        isOffsetFieldFocused = false
        undoEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option),
                  event.charactersIgnoringModifiers == "z",
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
            DispatchQueue.main.async { undoAction() }
            return nil
        }

        guard !didShowLaunchInstruction else {
            return
        }

        didShowLaunchInstruction = true
        showLaunchInstruction = true
    }

    private func checkHost() {
        DispatchQueue.global(qos: .utility).async {
            let payload = PTSLManager.shared().hostReadyStatus()
            DispatchQueue.main.async {
                if let ok = payload["ok"] as? Bool, ok {
                    isProToolsOnline = true
                    statusText = "Pro Tools ready"
                } else {
                    isProToolsOnline = false
                    statusText = (payload["error"] as? String) ?? "Pro Tools offline"
                }
            }
        }
    }

    private func loadEDL() {
        guard MusicEDLParser.isOffsetSyntaxValid(normalizedOffsetInput()) else {
            statusText = "Invalid offset: use HH:MM:SS:FF"
            return
        }

        isLoading = true
        statusText = "Reading selected Pro Tools tracks..."
        entries = []
        selectedEntryIDs = []
        foundTracks = []
        missingTracks = []
        mutedRegionCount = 0
        rawSessionInfo = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let payload = PTSLManager.shared().exportMusicEDLForSelectedTracks()
            DispatchQueue.main.async {
                handle(payload: payload)
            }
        }
    }

    private func handle(payload: [AnyHashable: Any]) {
        isLoading = false

        guard let ok = payload["ok"] as? Bool, ok else {
            statusText = (payload["error"] as? String) ?? "EDL export failed"
            return
        }

        sessionName = payload["session_name"] as? String ?? ""
        rawSessionInfo = payload["session_info"] as? String ?? ""
        foundTracks = payload["found_tracks"] as? [String] ?? []
        missingTracks = payload["missing_tracks"] as? [String] ?? []

        applyParsedResult(parseTargets: foundTracks, updateStatus: true)
    }

    private func reparseWithCurrentOffset(updateStatus: Bool) {
        guard !rawSessionInfo.isEmpty else {
            return
        }
        guard MusicEDLParser.isOffsetSyntaxValid(normalizedOffsetInput()) else {
            if updateStatus {
                statusText = "Invalid offset: use HH:MM:SS:FF"
            }
            return
        }

        let parseTargets = foundTracks
        guard !parseTargets.isEmpty else {
            return
        }
        applyParsedResult(parseTargets: parseTargets, updateStatus: updateStatus)
    }

    private func applyParsedResult(parseTargets: [String], updateStatus: Bool) {
        let result = MusicEDLParser.parse(rawSessionInfo, targetTracks: parseTargets, offset: normalizedOffsetInput())
        entries = result.entries.map { entry in
            var updated = entry
            updated.clipName = importTitleCase(entry.clipName)
            return updated
        }
        selectedEntryIDs = []
        mutedRegionCount = result.mutedRegionCount
        frameRate = result.frameRate

        if updateStatus {
            if entries.isEmpty {
                statusText = "No EDL rows found for \(parseTargets.joined(separator: ", "))"
            } else {
                let offsetSuffix = normalizedOffsetInput() == "00:00:00:00" ? "" : " - offset \(normalizedOffsetInput())"
                statusText = "Music cues loaded\(offsetSuffix)"
            }
        }
    }

    private func normalizedOffsetInput() -> String {
        var trimmed = offsetInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";", with: ":")
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("-") {
            trimmed.removeFirst()
        }
        let unsigned = trimmed.isEmpty ? "00:00:00:00" : trimmed
        return offsetSign == "-" && unsigned != "00:00:00:00" ? "-\(unsigned)" : unsigned
    }

    private func importTitleCase(_ value: String) -> String {
        let separators = CharacterSet(charactersIn: " \t\n\r-_./")
        var result = ""
        var shouldCapitalize = true

        for scalar in value.unicodeScalars {
            let character = String(scalar)
            if separators.contains(scalar) {
                result += character
                shouldCapitalize = true
            } else if shouldCapitalize {
                result += character.uppercased()
                shouldCapitalize = false
            } else {
                result += character.lowercased()
            }
        }

        return result
    }

    private func syncOffsetSignFromInputIfNeeded() {
        let trimmed = offsetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "+" || first == "-" else {
            return
        }
        offsetSign = String(first)
        offsetInput = String(trimmed.dropFirst())
    }

    private func binding(
        for entryID: MusicEDLEntry.ID,
        _ keyPath: WritableKeyPath<MusicEDLEntry, String>
    ) -> Binding<String> {
        Binding(
            get: {
                entries.first(where: { $0.id == entryID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                updateEntry(entryID) { entry in
                    entry[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func timeBinding(
        for entryID: MusicEDLEntry.ID,
        _ keyPath: WritableKeyPath<MusicEDLEntry, String>
    ) -> Binding<String> {
        Binding(
            get: {
                entries.first(where: { $0.id == entryID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                updateEntry(entryID) { entry in
                    entry[keyPath: keyPath] = newValue
                    let duration = MusicEDLParser.displayDuration(from: entry.startTime, to: entry.endTime, fps: frameRate)
                    if !duration.isEmpty {
                        entry.duration = duration
                    }
                }
            }
        )
    }

    private func updateEntry(_ entryID: MusicEDLEntry.ID, mutate: (inout MusicEDLEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        mutate(&entries[index])
    }

    private func saveUndoSnapshot() {
        undoStack.append(entries)
        if undoStack.count > 10 { undoStack.removeFirst() }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView), !entries.isEmpty else {
            return
        }

        let currentIndex: Int
        if let last = lastClickedIndex,
           entries.indices.contains(last),
           selectedEntryIDs.contains(entries[last].id) {
            currentIndex = last
        } else if let selectedIndex = entries.firstIndex(where: { selectedEntryIDs.contains($0.id) }) {
            currentIndex = selectedIndex
        } else {
            currentIndex = 0
        }

        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(0, currentIndex - 1)
        case .down:
            nextIndex = min(entries.count - 1, currentIndex + 1)
        default:
            return
        }

        selectedEntryIDs = [entries[nextIndex].id]
        lastClickedIndex = nextIndex
    }

    private func undoAction() {
        guard !undoStack.isEmpty else { return }
        entries = undoStack.removeLast()
        selectedEntryIDs = []
        lastClickedIndex = nil
        statusText = "Undone"
    }

    private func deleteSelectedEntries() {
        let idsToDelete = selectedEntryIDs
        guard !idsToDelete.isEmpty else { return }
        saveUndoSnapshot()
        entries.removeAll { idsToDelete.contains($0.id) }
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryIDs = []
        lastClickedIndex = nil
    }

    private func deleteEntry(_ entryID: MusicEDLEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        saveUndoSnapshot()
        let name = entries[index].clipName
        entries.remove(at: index)
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryIDs.remove(entryID)
        if selectedEntryIDs.isEmpty && !entries.isEmpty {
            let newIdx = min(index, entries.count - 1)
            selectedEntryIDs = [entries[newIdx].id]
        }
        statusText = "Deleted row: \(name)"
    }

    private func mergeSelectedEntries() {
        guard selectedEntryIDs.count >= 2 else { return }

        let selectedIndices = entries.indices.filter { selectedEntryIDs.contains(entries[$0].id) }.sorted()
        guard let firstIndex = selectedIndices.first,
              let lastIndex = selectedIndices.last,
              firstIndex < entries.count,
              lastIndex < entries.count,
              firstIndex != lastIndex else { return }

        let selected = selectedIndices.map { entries[$0] }
        let first = entries[firstIndex]
        let last = entries[lastIndex]

        saveUndoSnapshot()

        var merged = first
        merged.startTime = first.startTime
        merged.endTime = last.endTime

        let dur = MusicEDLParser.displayDuration(from: merged.startTime, to: merged.endTime, fps: frameRate)
        if !dur.isEmpty { merged.duration = dur }

        let idsToRemove = Set(selected.dropFirst().map(\.id))
        entries.removeAll { idsToRemove.contains($0.id) }

        if let idx = entries.firstIndex(where: { $0.id == first.id }) { entries[idx] = merged }
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryIDs = [first.id]
        lastClickedIndex = entries.firstIndex(where: { $0.id == first.id })
        statusText = "Merged \(selected.count) rows"
    }

    private func clearEDL() {
        endTextEditing()
        entries = []
        selectedEntryIDs = []
        lastClickedIndex = nil
        sessionName = ""
        foundTracks = []
        missingTracks = []
        mutedRegionCount = 0
        rawSessionInfo = ""
        statusText = "Cleared"
    }

    private func endTextEditing() {
        isOffsetFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func copyToPasteboard(_ value: String, status: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusText = status
    }

    private func pasteTimecode(into entryID: MusicEDLEntry.ID, keyPath: WritableKeyPath<MusicEDLEntry, String>) {
        let rawValue = NSPasteboard.general.string(forType: .string) ?? ""
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MusicEDLParser.isTimecodeSyntaxValid(value) else {
            statusText = "Clipboard: invalid timecode"
            return
        }

        saveUndoSnapshot()
        updateEntry(entryID) { entry in
            entry[keyPath: keyPath] = value
            let duration = MusicEDLParser.displayDuration(from: entry.startTime, to: entry.endTime, fps: frameRate)
            if !duration.isEmpty {
                entry.duration = duration
            }
        }
        selectedEntryIDs = [entryID]
        statusText = "Timecode pasted"
    }

    private func csvRow(_ entry: MusicEDLEntry) -> String {
        [entry.event, entry.clipName, entry.startTime, entry.endTime, entry.duration]
            .map(csvEscape)
            .joined(separator: ",")
    }

    private func csvString() -> String {
        let header = ["No", "Name", "In", "Out", "Duration"]
        let rows = entries.map {
            [$0.event, $0.clipName, $0.startTime, $0.endTime, $0.duration]
        }
        return ([header] + rows).map { row in
            row.map(csvEscape).joined(separator: ",")
        }.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func copyCSV() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csvString(), forType: .string)
        statusText = "CSV copied to clipboard"
    }

    private func copyRawSessionInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawSessionInfo, forType: .string)
        statusText = "Raw Session Info copied"
    }

    private func importMarkers() {
        openMarkerSettings()
    }

    private func openMarkerSettings() {
        showMarkerSettings = true
        refreshMarkerRulerOptions()
    }

    private func refreshMarkerRulerOptions() {
        isLoadingMarkerRulers = true
        DispatchQueue.global(qos: .userInitiated).async {
            let payload = PTSLManager.shared().availableMarkerRulerNames()
            DispatchQueue.main.async {
                isLoadingMarkerRulers = false
                let names = (payload["ruler_names"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let uniqueNames = Array(NSOrderedSet(array: ["Markers"] + names)) as? [String] ?? ["Markers"]
                markerRulerOptions = uniqueNames
                if !markerRulerName.isEmpty && !markerRulerOptions.contains(markerRulerName) {
                    markerRulerOptions.append(markerRulerName)
                }
                if markerRulerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    markerRulerName = markerRulerOptions.first ?? "Markers"
                }
            }
        }
    }

    private func performImportMarkers() {
        guard !entries.isEmpty else {
            statusText = "No rows to import"
            return
        }

        let invalidEntries = entries.filter {
            !MusicEDLParser.isTimecodeSyntaxValid($0.startTime)
                || (!$0.endTime.isEmpty && !MusicEDLParser.isTimecodeSyntaxValid($0.endTime))
        }
        guard invalidEntries.isEmpty else {
            statusText = "Import canceled: fix invalid timecodes"
            return
        }

        let markers = markerPayloads()
        isImportingMarkers = true
        statusText = "Importing markers into Pro Tools..."

        DispatchQueue.global(qos: .userInitiated).async {
            let payload = PTSLManager.shared().importMusicMarkers(markers)
            DispatchQueue.main.async {
                isImportingMarkers = false

                let successCount = (payload["success_count"] as? NSNumber)?.intValue ?? payload["success_count"] as? Int ?? 0
                let failureCount = (payload["failure_count"] as? NSNumber)?.intValue ?? payload["failure_count"] as? Int ?? 0

                if successCount > 0 && failureCount == 0 {
                    statusText = "\(successCount) marker(s) imported into the session"
                } else if successCount > 0 {
                    statusText = "\(successCount) marker(s) imported, \(failureCount) error(s)"
                } else {
                    let message = payload["error"] as? String
                        ?? (payload["failure_list"] as? [String])?.first
                        ?? "Import markers impossible"
                    statusText = message
                }
            }
        }
    }

    private func markerPayloads() -> [[String: Any]] {
        entries.enumerated().map { index, entry in
            [
                "name": markerName(for: entry, index: index),
                "start_time": entry.startTime,
                "end_time": entry.endTime,
                "comments": markerComment(for: entry),
                "color_index": markerColorIndex,
                "ruler_name": markerRulerName
            ]
        }
    }

    private func markerName(for entry: MusicEDLEntry, index: Int) -> String {
        let name = entry.clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Music \(index + 1)" : name
    }

    private func markerComment(for entry: MusicEDLEntry) -> String {
        [
            "Odile",
            "In: \(entry.startTime)",
            "Out: \(entry.endTime)",
            "Duration: \(entry.duration)"
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }

    private func exportXLSX() {
        showXLSXPreview = true
    }

    private func performExportXLSX() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultXLSXName()
        panel.allowedContentTypes = [.excelWorkbook]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try XLSXExporter.makeWorkbook(
                    entries: entries,
                    sessionName: sessionName,
                    selectedTracks: foundTracks,
                    offset: normalizedOffsetInput(),
                    settings: xlsxSettings
                )
                try data.write(to: url, options: .atomic)
                statusText = "XLSX exporté: \(url.lastPathComponent)"
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func defaultXLSXName() -> String {
        let base = sessionName.isEmpty ? "Music_EDL" : sessionName
        let safe = base
            .replacingOccurrences(of: #"[^\w.-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return "\(safe.isEmpty ? "Music_EDL" : safe)_music-edl.xlsx"
    }
}

private enum XLSXExporter {
    static func makeWorkbook(
        entries: [MusicEDLEntry],
        sessionName: String,
        selectedTracks: [String],
        offset: String,
        settings: XLSXExportSettings = XLSXExportSettings()
    ) throws -> Data {
        var archive = ZipArchive()
        let worksheet = worksheetXML(
            entries: entries,
            sessionName: sessionName,
            selectedTracks: selectedTracks,
            offset: offset
        )

        archive.add(path: "[Content_Types].xml", text: contentTypesXML)
        archive.add(path: "_rels/.rels", text: rootRelsXML)
        archive.add(path: "docProps/app.xml", text: appXML)
        archive.add(path: "docProps/core.xml", text: coreXML(sessionName: sessionName))
        archive.add(path: "xl/workbook.xml", text: workbookXML)
        archive.add(path: "xl/_rels/workbook.xml.rels", text: workbookRelsXML)
        archive.add(path: "xl/styles.xml", text: stylesXML(settings: settings))
        archive.add(path: "xl/worksheets/sheet1.xml", text: worksheet)
        return archive.finalize()
    }

    private static func worksheetXML(
        entries: [MusicEDLEntry],
        sessionName: String,
        selectedTracks: [String],
        offset: String
    ) -> String {
        let headerRowIndex = 5
        let firstEntryRowIndex = headerRowIndex + 1
        let lastRow = max(entries.count + firstEntryRowIndex - 1, headerRowIndex)
        let title = "\(sessionName.isEmpty ? "Music" : sessionName) EDL"
        let subtitle = "Date: \(displayDate())"
        let headers = ["No", "Name", "In", "Out", "Duration"]
        let headerStyles = [2, 2, 2, 2, 2]

        let titleCells = (1...5).map { column in
            cell(column: column, row: 1, value: column == 1 ? title : "", style: 1)
        }
        let dateCells = (1...5).map { column in
            cell(column: column, row: 2, value: column == 1 ? subtitle : "", style: 7)
        }
        let headerRow = row(headerRowIndex, height: 28, cells: headers.enumerated().map { column, value in
            cell(column: column + 1, row: headerRowIndex, value: value, style: headerStyles[column])
        })

        let entryRows = entries.enumerated().map { index, entry in
            let rowIndex = index + firstEntryRowIndex
            let nameStyle = index.isMultiple(of: 2) ? 3 : 4
            let rowStyle = index.isMultiple(of: 2) ? 5 : 6
            let name = entry.clipName
            return row(rowIndex, height: rowHeight(forName: name), cells: [
                cell(column: 1, row: rowIndex, value: entry.event, style: rowStyle),
                cell(column: 2, row: rowIndex, value: name, style: nameStyle),
                cell(column: 3, row: rowIndex, value: entry.startTime, style: rowStyle),
                cell(column: 4, row: rowIndex, value: entry.endTime, style: rowStyle),
                cell(column: 5, row: rowIndex, value: entry.duration, style: rowStyle)
            ])
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <dimension ref="A1:E\(lastRow)"/>
          <sheetViews>
            <sheetView workbookViewId="0" showGridLines="0">
              <pane ySplit="5" topLeftCell="A6" activePane="bottomLeft" state="frozen"/>
              <selection pane="bottomLeft" activeCell="A6" sqref="A6"/>
            </sheetView>
          </sheetViews>
          <sheetFormatPr defaultRowHeight="24"/>
          <cols>
            <col min="1" max="1" width="8" customWidth="1"/>
            <col min="2" max="2" width="54" customWidth="1"/>
            <col min="3" max="5" width="15" customWidth="1"/>
          </cols>
          <sheetData>
            \(row(1, height: 34, cells: titleCells))
            \(row(2, height: 26, cells: dateCells))
            \(row(3, height: 12, cells: []))
            \(row(4, height: 8, cells: []))
            \(headerRow)
            \(entryRows)
          </sheetData>
          <autoFilter ref="A\(headerRowIndex):E\(lastRow)"/>
          <mergeCells count="2">
            <mergeCell ref="A1:E1"/>
            <mergeCell ref="A2:E2"/>
          </mergeCells>
          <pageMargins left="0.45" right="0.45" top="0.65" bottom="0.65" header="0.3" footer="0.3"/>
        </worksheet>
        """
    }

    private static func row(_ index: Int, height: Double, cells: [String]) -> String {
        let heightValue = String(format: "%.1f", height)
        return "<row r=\"\(index)\" ht=\"\(heightValue)\" customHeight=\"1\">\(cells.joined())</row>"
    }

    private static func rowHeight(forName name: String) -> Double {
        if name.contains("\n") || name.count > 44 {
            return 42
        }
        return 32
    }

    private static func cell(column: Int, row: Int, value: String, style: Int) -> String {
        let reference = "\(columnName(column))\(row)"
        return "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
    }

    private static func columnName(_ index: Int) -> String {
        var number = index
        var name = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            number = (number - 1) / 26
        }
        return name
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func displayDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let appXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
      <Application>Odile</Application>
    </Properties>
    """

    private static func coreXML(sessionName: String) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let title = sessionName.isEmpty ? "Music EDL" : sessionName
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(xmlEscape(title))</dc:title>
          <dc:creator>Odile</dc:creator>
          <cp:lastModifiedBy>Odile</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Music EDL" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """

        private static let workbookRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

        private static func colorToHex(_ color: Color) -> String {
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                var r: CGFloat = 0
                var g: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                ns.getRed(&r, green: &g, blue: &b, alpha: &a)
                return String(format: "FF%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }

        private static func stylesXML(settings: XLSXExportSettings) -> String {
                let headerHex = colorToHex(settings.headerFill)
                let evenHex = colorToHex(settings.rowFillEven)
                let oddHex = colorToHex(settings.rowFillOdd)
                return """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                    <fonts count="6">
                        <font><sz val="11"/><color rgb="FF17202A"/><name val="Calibri"/></font>
                        <font><b/><sz val="16"/><color rgb="FF1F2933"/><name val="Calibri"/></font>
                        <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
                        <font><sz val="11"/><color rgb="FF17202A"/><name val="Calibri"/></font>
                        <font><i/><sz val="10"/><color rgb="FF585858"/><name val="Calibri"/></font>
                        <font><b/><sz val="11"/><color rgb="FF111111"/><name val="Calibri"/></font>
                    </fonts>
                    <fills count="11">
                        <fill><patternFill patternType="none"/></fill>
                        <fill><patternFill patternType="gray125"/></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="\(headerHex)"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="\(evenHex)"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="\(oddHex)"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="FFC67FAE"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="FFD7E8BC"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="FF98DDDE"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="FFA6BE47"/><bgColor indexed="64"/></patternFill></fill>
                        <fill><patternFill patternType="solid"><fgColor rgb="FF2E5283"/><bgColor indexed="64"/></patternFill></fill>
                    </fills>
                    <borders count="2">
                        <border><left/><right/><top/><bottom/><diagonal/></border>
                        <border>
                            <left style="thin"><color rgb="FFD9D9D9"/></left>
                            <right style="thin"><color rgb="FFD9D9D9"/></right>
                            <top style="thin"><color rgb="FFD9D9D9"/></top>
                            <bottom style="thin"><color rgb="FFD9D9D9"/></bottom>
                            <diagonal/>
                        </border>
                    </borders>
                    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
                    <cellXfs count="13">
                        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
                        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment horizontal="left" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
                        <xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
                        <xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="4" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment horizontal="left" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="2" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="5" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="5" fillId="8" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                        <xf numFmtId="0" fontId="5" fillId="9" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
                    </cellXfs>
                    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
                    <dxfs count="0"/>
                    <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleMedium9"/>
                </styleSheet>
                """
        }
}

private struct ZipArchive {
    private struct CentralDirectoryEntry {
        let path: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var data = Data()
    private var entries: [CentralDirectoryEntry] = []

    mutating func add(path: String, text: String) {
        add(path: path, data: Data(text.utf8))
    }

    mutating func add(path: String, data fileData: Data) {
        let pathData = Data(path.utf8)
        let crc = CRC32.checksum(fileData)
        let offset = UInt32(data.count)
        let size = UInt32(fileData.count)

        data.appendUInt32LE(0x04034b50)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(crc)
        data.appendUInt32LE(size)
        data.appendUInt32LE(size)
        data.appendUInt16LE(UInt16(pathData.count))
        data.appendUInt16LE(0)
        data.append(pathData)
        data.append(fileData)

        entries.append(CentralDirectoryEntry(path: path, crc: crc, size: size, offset: offset))
    }

    mutating func finalize() -> Data {
        let centralDirectoryOffset = UInt32(data.count)

        for entry in entries {
            let pathData = Data(entry.path.utf8)
            data.appendUInt32LE(0x02014b50)
            data.appendUInt16LE(20)
            data.appendUInt16LE(20)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(entry.crc)
            data.appendUInt32LE(entry.size)
            data.appendUInt32LE(entry.size)
            data.appendUInt16LE(UInt16(pathData.count))
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(0)
            data.appendUInt32LE(entry.offset)
            data.append(pathData)
        }

        let centralDirectorySize = UInt32(data.count) - centralDirectoryOffset
        data.appendUInt32LE(0x06054b50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(UInt16(entries.count))
        data.appendUInt16LE(UInt16(entries.count))
        data.appendUInt32LE(centralDirectorySize)
        data.appendUInt32LE(centralDirectoryOffset)
        data.appendUInt16LE(0)

        return data
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

private extension UTType {
    static let excelWorkbook = UTType(filenameExtension: "xlsx")!
}

struct XLSXExportSettings {
    var headerFill: Color = AppTheme.backgroundTop
    var rowFillEven: Color = Color(hex: "FFFFFF")
    var rowFillOdd: Color = Color(hex: "F4F4F4")
}

private struct NameCellView: View {
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

private struct MarkersSettingsSheet: View {
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

private struct XLSXPreviewSheet: View {
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

private struct GogoToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .padding(.horizontal, 10)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 0.58) : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.glassHighlight.opacity(1.5), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: tint.opacity(isEnabled ? 0.42 : 0), radius: 14, x: 0, y: 6)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

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

private struct MusicEDLColorSection: Identifiable {
    let id: String
    let title: String
    let keys: [MusicEDLColorKey]
}

private struct MusicEDLColorEditorRow: View {
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

private extension View {
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
