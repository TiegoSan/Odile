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
    @State private var selectedEntryID: MusicEDLEntry.ID?
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
        .alert("Select tracks in Protools then click Load", isPresented: $showLaunchInstruction) {
            Button("OK", role: .cancel) {}
        }
        .onDeleteCommand(perform: deleteSelectedEntry)
    }

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                Image("LogoGogoLabs")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .offset(x: 20, y: -10)
                    .shadow(color: AppTheme.accent.opacity(0.44), radius: 18, x: 0, y: 8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Odile")
                        .font(.custom("Lobster-Regular", size: 65))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(y: -15)

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
                        .offset(y: -25)
                }
                .frame(width: 316, height: 90, alignment: .center)
                .offset(x: -16, y: -7)
            }
            .frame(width: 430, height: 90, alignment: .leading)

            toolbarControl(width: 204, help: "Apply a TC offset.") {
                HStack(spacing: 6) {
                    Picker("", selection: $offsetSign) {
                        Text("+").tag("+")
                        Text("-").tag("-")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 58)
                    .onChange(of: offsetSign) { _ in
                        reparseWithCurrentOffset(updateStatus: false)
                    }

                    TextField("00:00:00:00", text: $offsetInput)
                        .gogoTimecodeField(font: .system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(width: 140)
                        .help("Offset HH:MM:SS:FF")
                        .focused($isOffsetFieldFocused)
                        .onSubmit {
                            reparseWithCurrentOffset(updateStatus: true)
                            endTextEditing()
                        }
                        .onChange(of: offsetInput) { _ in
                            syncOffsetSignFromInputIfNeeded()
                            reparseWithCurrentOffset(updateStatus: false)
                        }
                }
            }

            toolbarButton("Load", systemImage: "arrow.clockwise", help: "Read PT tracks.", tint: AppTheme.buttonLoad, disabled: isLoading, action: loadEDL)
                .keyboardShortcut("r", modifiers: [.command])
            toolbarButton(isImportingMarkers ? "Importing" : "Markers", systemImage: "mappin.and.ellipse", help: "Send markers.", tint: AppTheme.buttonMarkers, disabled: entries.isEmpty || isImportingMarkers, action: importMarkers)
            toolbarButton("Delete", systemImage: "trash", help: "Remove row.", tint: AppTheme.buttonDelete, disabled: selectedEntryID == nil, action: deleteSelectedEntry)
            toolbarButton("Copy", systemImage: "doc.on.doc", help: "Copy CSV.", tint: AppTheme.buttonCopy, disabled: entries.isEmpty, action: copyCSV)
            toolbarButton("XLSX", systemImage: "square.and.arrow.down", help: "Export file.", tint: AppTheme.buttonExport, disabled: entries.isEmpty, action: exportXLSX)

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

    private var table: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider().overlay(AppTheme.softBorder)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        editableRow(entry: entry, index: index)
                    }
                }
            }
            .background(AppTheme.backgroundBottom)
        }
        .background(AppTheme.backgroundBottom)
    }

    private var tableColumns: [GridItem] {
        [
            GridItem(.fixed(52), spacing: 0, alignment: .leading),
            GridItem(.flexible(minimum: 360), spacing: 0, alignment: .leading),
            GridItem(.fixed(112), spacing: 0, alignment: .leading),
            GridItem(.fixed(112), spacing: 0, alignment: .leading),
            GridItem(.fixed(100), spacing: 0, alignment: .leading),
            GridItem(.fixed(42), spacing: 0, alignment: .center)
        ]
    }

    private var tableHeader: some View {
        LazyVGrid(columns: tableColumns, alignment: .leading, spacing: 0) {
            headerCell("No")
            headerCell("Name")
            headerCell("In")
            headerCell("Out")
            headerCell("Duration")
            headerCell("")
        }
        .frame(minHeight: 38)
        .background(AppTheme.card.opacity(0.92))
    }

    private func editableRow(entry: MusicEDLEntry, index: Int) -> some View {
        let isSelected = selectedEntryID == entry.id
        return LazyVGrid(columns: tableColumns, alignment: .leading, spacing: 0) {
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
            selectedEntryID = entry.id
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

    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .overlay(alignment: .trailing) {
                if !title.isEmpty {
                    Rectangle()
                        .fill(AppTheme.softBorder)
                        .frame(width: 1, height: 18)
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
        TextField("", text: value, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(AppTheme.textPrimary)
            .lineLimit(1...4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
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
                .foregroundColor((isLoading || isImportingMarkers) ? AppTheme.accent : AppTheme.textSecondary)
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
                    statusText = "Pro Tools ready"
                } else if let error = payload["error"] as? String {
                    statusText = error
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
        selectedEntryID = nil
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
        entries = result.entries
        selectedEntryID = nil
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

    private func deleteSelectedEntry() {
        guard let selectedEntryID else {
            return
        }
        deleteEntry(selectedEntryID)
    }

    private func deleteEntry(_ entryID: MusicEDLEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        let name = entries[index].clipName
        entries.remove(at: index)
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryID = entries.indices.contains(index) ? entries[index].id : entries.last?.id
        statusText = "Deleted row: \(name)"
    }

    private func clearEDL() {
        endTextEditing()
        entries = []
        selectedEntryID = nil
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

        updateEntry(entryID) { entry in
            entry[keyPath: keyPath] = value
            let duration = MusicEDLParser.displayDuration(from: entry.startTime, to: entry.endTime, fps: frameRate)
            if !duration.isEmpty {
                entry.duration = duration
            }
        }
        selectedEntryID = entryID
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
                "comments": markerComment(for: entry)
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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultXLSXName()
        panel.allowedContentTypes = [.excelWorkbook]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                let data = try XLSXExporter.makeWorkbook(
                    entries: entries,
                    sessionName: sessionName,
                    selectedTracks: foundTracks,
                    offset: normalizedOffsetInput()
                )
                try data.write(to: url, options: .atomic)
                statusText = "XLSX exporte: \(url.lastPathComponent)"
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
        offset: String
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
        archive.add(path: "xl/styles.xml", text: stylesXML)
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
        let headerStyles = [8, 9, 10, 11, 12]

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
            let style = index.isMultiple(of: 2) ? 3 : 4
            let name = titleCaseName(entry.clipName)
            return row(rowIndex, height: rowHeight(forName: name), cells: [
                cell(column: 1, row: rowIndex, value: entry.event, style: 5),
                cell(column: 2, row: rowIndex, value: name, style: style),
                cell(column: 3, row: rowIndex, value: entry.startTime, style: 6),
                cell(column: 4, row: rowIndex, value: entry.endTime, style: 6),
                cell(column: 5, row: rowIndex, value: entry.duration, style: 6)
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

    private static func titleCaseName(_ value: String) -> String {
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

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="6">
        <font><sz val="11"/><color rgb="FF17202A"/><name val="Aptos"/></font>
        <font><b/><sz val="16"/><color rgb="FF1F2933"/><name val="Aptos Display"/></font>
        <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>
        <font><sz val="11"/><color rgb="FF17202A"/><name val="Aptos"/></font>
        <font><i/><sz val="10"/><color rgb="FF585858"/><name val="Aptos"/></font>
        <font><b/><sz val="11"/><color rgb="FF111111"/><name val="Aptos"/></font>
      </fonts>
      <fills count="11">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFA66E4A"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFF4F4F4"/><bgColor indexed="64"/></patternFill></fill>
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
        <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="left" vertical="center"/></xf>
        <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="4" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="left" vertical="center"/></xf>
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
            keys: [.buttonLoad, .buttonMarkers, .buttonDelete, .buttonCopy, .buttonExport, .buttonColors]
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
                .buttonStyle(GogoToolbarButtonStyle(tint: AppTheme.buttonColors))
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
