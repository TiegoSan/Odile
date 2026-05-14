
import SwiftUI
import UniformTypeIdentifiers

final class OdileViewModel: ObservableObject {
    var undoEventMonitor: Any? = nil
    @Published var offsetSign = "+"
    @Published var offsetInput = "00:00:00:00"
    @Published var entries: [MusicEDLEntry] = []
    @Published var statusText = "Ready"
    @Published var sessionName = ""
    @Published var foundTracks: [String] = []
    @Published var missingTracks: [String] = []
    @Published var mutedRegionCount = 0
    @Published var rawSessionInfo = ""
    @Published var isLoading = false
    @Published var isImportingMarkers = false
    @Published var frameRate = 25
    @Published var selectedEntryIDs: Set<MusicEDLEntry.ID> = []
    @Published var lastClickedIndex: Int? = nil
    @Published var undoStack: [[MusicEDLEntry]] = []
    @Published var columnWidths: [CGFloat] = [52, 540, 132, 132, 122]
    @Published var dragStartWidths: [Int: CGFloat] = [:]
    @Published var isProToolsOnline = false
    @Published var showMarkerSettings = false
    @Published var markerColorIndex: Int = 1
    @Published var markerRulerName: String = "Markers"
    @Published var markerRulerOptions: [String] = ["Markers"]
    @Published var isLoadingMarkerRulers = false
    @Published var showXLSXPreview = false
    @Published var xlsxSettings = XLSXExportSettings()
    @Published var showLaunchInstruction = false
    @Published var didShowLaunchInstruction = false

    func handleAppear() {
        checkHost()
        // isOffsetFieldFocused = false
        undoEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option),
                  event.charactersIgnoringModifiers == "z",
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
            DispatchQueue.main.async { [weak self] in guard let self = self else { return }
undoAction() }
            return nil
        }

        guard !didShowLaunchInstruction else {
            return
        }

        didShowLaunchInstruction = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.showLaunchInstruction = true
        }
    }

    func checkHost() {
        DispatchQueue.global(qos: .utility).async {
            let payload = PTSLManager.shared().hostReadyStatus()
            DispatchQueue.main.async { [weak self] in guard let self = self else { return }
                if let ok = payload["ok"] as? Bool, ok {
                    isProToolsOnline = true
                    self.statusText = "Pro Tools ready"
                } else {
                    isProToolsOnline = false
                    self.statusText = (payload["error"] as? String) ?? "Pro Tools offline"
                }
            }
        }
    }

    func loadEDL() {
        guard MusicEDLParser.isOffsetSyntaxValid(normalizedOffsetInput()) else {
            self.statusText = "Invalid offset: use HH:MM:SS:FF"
            return
        }

        isLoading = true
        self.statusText = "Reading selected Pro Tools tracks..."
        entries = []
        selectedEntryIDs = []
        foundTracks = []
        missingTracks = []
        mutedRegionCount = 0
        rawSessionInfo = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let payload = PTSLManager.shared().exportMusicEDLForSelectedTracks()
            DispatchQueue.main.async { [weak self] in guard let self = self else { return }
                handle(payload: payload)
            }
        }
    }

    func handle(payload: [AnyHashable: Any]) {
        isLoading = false

        guard let ok = payload["ok"] as? Bool, ok else {
            self.statusText = (payload["error"] as? String) ?? "EDL export failed"
            return
        }

        sessionName = payload["session_name"] as? String ?? ""
        rawSessionInfo = payload["session_info"] as? String ?? ""
        foundTracks = payload["found_tracks"] as? [String] ?? []
        missingTracks = payload["missing_tracks"] as? [String] ?? []

        applyParsedResult(parseTargets: foundTracks, updateStatus: true)
    }

    func reparseWithCurrentOffset(updateStatus: Bool) {
        guard !rawSessionInfo.isEmpty else {
            return
        }
        guard MusicEDLParser.isOffsetSyntaxValid(normalizedOffsetInput()) else {
            if updateStatus {
                self.statusText = "Invalid offset: use HH:MM:SS:FF"
            }
            return
        }

        let parseTargets = foundTracks
        guard !parseTargets.isEmpty else {
            return
        }
        applyParsedResult(parseTargets: parseTargets, updateStatus: updateStatus)
    }

    func applyParsedResult(parseTargets: [String], updateStatus: Bool) {
        let result = MusicEDLParser.parse(rawSessionInfo, targetTracks: parseTargets, offset: self.normalizedOffsetInput())
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
                self.statusText = "No EDL rows found for \(parseTargets.joined(separator: ", "))"
            } else {
                let offsetSuffix = normalizedOffsetInput() == "00:00:00:00" ? "" : " - offset \(normalizedOffsetInput())"
                self.statusText = "Music cues loaded\(offsetSuffix)"
            }
        }
    }

    func normalizedOffsetInput() -> String {
        var trimmed = offsetInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";", with: ":")
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("-") {
            trimmed.removeFirst()
        }
        let unsigned = trimmed.isEmpty ? "00:00:00:00" : trimmed
        return offsetSign == "-" && unsigned != "00:00:00:00" ? "-\(unsigned)" : unsigned
    }

    func importTitleCase(_ value: String) -> String {
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

    func syncOffsetSignFromInputIfNeeded() {
        let trimmed = offsetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "+" || first == "-" else {
            return
        }
        offsetSign = String(first)
        offsetInput = String(trimmed.dropFirst())
    }

    func binding(
        for entryID: MusicEDLEntry.ID,
        _ keyPath: WritableKeyPath<MusicEDLEntry, String>
    ) -> Binding<String> {
        Binding(
            get: {
                self.entries.first(where: { $0.id == entryID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                self.updateEntry(entryID) { entry in
                    entry[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func timeBinding(
        for entryID: MusicEDLEntry.ID,
        _ keyPath: WritableKeyPath<MusicEDLEntry, String>
    ) -> Binding<String> {
        Binding(
            get: {
                self.entries.first(where: { $0.id == entryID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                self.updateEntry(entryID) { entry in
                    entry[keyPath: keyPath] = newValue
                    let duration = MusicEDLParser.displayDuration(from: entry.startTime, to: entry.endTime, fps: self.frameRate)
                    if !duration.isEmpty {
                        entry.duration = duration
                    }
                }
            }
        )
    }

    func updateEntry(_ entryID: MusicEDLEntry.ID, mutate: (inout MusicEDLEntry) -> Void) {
        guard let index = self.entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        mutate(&entries[index])
    }

    func saveUndoSnapshot() {
        undoStack.append(entries)
        if undoStack.count > 10 { undoStack.removeFirst() }
    }

    func moveSelection(_ direction: MoveCommandDirection) {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView), !entries.isEmpty else {
            return
        }

        let currentIndex: Int
        if let last = lastClickedIndex,
           entries.indices.contains(last),
           selectedEntryIDs.contains(entries[last].id) {
            currentIndex = last
        } else if let selectedIndex = self.entries.firstIndex(where: { selectedEntryIDs.contains($0.id) }) {
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

    func undoAction() {
        guard !undoStack.isEmpty else { return }
        entries = undoStack.removeLast()
        selectedEntryIDs = []
        lastClickedIndex = nil
        self.statusText = "Undone"
    }

    func deleteSelectedEntries() {
        let idsToDelete = selectedEntryIDs
        guard !idsToDelete.isEmpty else { return }
        saveUndoSnapshot()
        entries.removeAll { idsToDelete.contains($0.id) }
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryIDs = []
        lastClickedIndex = nil
    }

    func deleteEntry(_ entryID: MusicEDLEntry.ID) {
        guard let index = self.entries.firstIndex(where: { $0.id == entryID }) else { return }
        saveUndoSnapshot()
        let name = entries[index].clipName
        entries.remove(at: index)
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryIDs.remove(entryID)
        if selectedEntryIDs.isEmpty && !entries.isEmpty {
            let newIdx = min(index, entries.count - 1)
            selectedEntryIDs = [entries[newIdx].id]
        }
        self.statusText = "Deleted row: \(name)"
    }

    func mergeSelectedEntries() {
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

        let dur = MusicEDLParser.displayDuration(from: merged.startTime, to: merged.endTime, fps: self.frameRate)
        if !dur.isEmpty { merged.duration = dur }

        let idsToRemove = Set(selected.dropFirst().map(\.id))
        entries.removeAll { idsToRemove.contains($0.id) }

        if let idx = self.entries.firstIndex(where: { $0.id == first.id }) { entries[idx] = merged }
        entries = MusicEDLParser.renumberEvents(entries)
        selectedEntryIDs = [first.id]
        lastClickedIndex = self.entries.firstIndex(where: { $0.id == first.id })
        self.statusText = "Merged \(selected.count) rows"
    }

    func clearEDL() {
        endTextEditing()
        entries = []
        selectedEntryIDs = []
        lastClickedIndex = nil
        sessionName = ""
        foundTracks = []
        missingTracks = []
        mutedRegionCount = 0
        rawSessionInfo = ""
        self.statusText = "Cleared"
    }

    func endTextEditing() {
        // isOffsetFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func copyToPasteboard(_ value: String, status: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        self.statusText = status
    }

    func pasteTimecode(into entryID: MusicEDLEntry.ID, keyPath: WritableKeyPath<MusicEDLEntry, String>) {
        let rawValue = NSPasteboard.general.string(forType: .string) ?? ""
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MusicEDLParser.isTimecodeSyntaxValid(value) else {
            self.statusText = "Clipboard: invalid timecode"
            return
        }

        saveUndoSnapshot()
        self.updateEntry(entryID) { entry in
            entry[keyPath: keyPath] = value
            let duration = MusicEDLParser.displayDuration(from: entry.startTime, to: entry.endTime, fps: self.frameRate)
            if !duration.isEmpty {
                entry.duration = duration
            }
        }
        selectedEntryIDs = [entryID]
        self.statusText = "Timecode pasted"
    }

    func csvRow(_ entry: MusicEDLEntry) -> String {
        [entry.event, entry.clipName, entry.startTime, entry.endTime, entry.duration]
            .map(csvEscape)
            .joined(separator: ",")
    }

    func csvString() -> String {
        let header = ["No", "Name", "In", "Out", "Duration"]
        let rows = entries.map {
            [$0.event, $0.clipName, $0.startTime, $0.endTime, $0.duration]
        }
        return ([header] + rows).map { row in
            row.map(csvEscape).joined(separator: ",")
        }.joined(separator: "\n")
    }

    func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    func copyCSV() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csvString(), forType: .string)
        self.statusText = "CSV copied to clipboard"
    }

    func copyRawSessionInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawSessionInfo, forType: .string)
        self.statusText = "Raw Session Info copied"
    }

    func importMarkers() {
        openMarkerSettings()
    }

    func openMarkerSettings() {
        showMarkerSettings = true
        refreshMarkerRulerOptions()
    }

    func refreshMarkerRulerOptions() {
        isLoadingMarkerRulers = true
        DispatchQueue.global(qos: .userInitiated).async {
            let payload = PTSLManager.shared().availableMarkerRulerNames()
            DispatchQueue.main.async { [weak self] in guard let self = self else { return }
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

    func performImportMarkers() {
        guard !entries.isEmpty else {
            self.statusText = "No rows to import"
            return
        }

        let invalidEntries = entries.filter {
            !MusicEDLParser.isTimecodeSyntaxValid($0.startTime)
                || (!$0.endTime.isEmpty && !MusicEDLParser.isTimecodeSyntaxValid($0.endTime))
        }
        guard invalidEntries.isEmpty else {
            self.statusText = "Import canceled: fix invalid timecodes"
            return
        }

        let markers = markerPayloads()
        isImportingMarkers = true
        self.statusText = "Importing markers into Pro Tools..."

        DispatchQueue.global(qos: .userInitiated).async {
            let payload = PTSLManager.shared().importMusicMarkers(markers)
            DispatchQueue.main.async { [weak self] in guard let self = self else { return }
                isImportingMarkers = false

                let successCount = (payload["success_count"] as? NSNumber)?.intValue ?? payload["success_count"] as? Int ?? 0
                let failureCount = (payload["failure_count"] as? NSNumber)?.intValue ?? payload["failure_count"] as? Int ?? 0

                if successCount > 0 && failureCount == 0 {
                    self.statusText = "\(successCount) marker(s) imported into the session"
                } else if successCount > 0 {
                    self.statusText = "\(successCount) marker(s) imported, \(failureCount) error(s)"
                } else {
                    let message = payload["error"] as? String
                        ?? (payload["failure_list"] as? [String])?.first
                        ?? "Import markers impossible"
                    self.statusText = message
                }
            }
        }
    }

    func markerPayloads() -> [[String: Any]] {
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

    func markerName(for entry: MusicEDLEntry, index: Int) -> String {
        let name = entry.clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Music \(index + 1)" : name
    }

    func markerComment(for entry: MusicEDLEntry) -> String {
        [
            "Odile",
            "In: \(entry.startTime)",
            "Out: \(entry.endTime)",
            "Duration: \(entry.duration)"
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }

    func exportXLSX() {
        showXLSXPreview = true
    }

    func performExportXLSX() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultXLSXName()
        panel.allowedContentTypes = [.excelWorkbook]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try XLSXExporter.makeWorkbook(
                    entries: self.entries,
                    sessionName: self.sessionName,
                    selectedTracks: self.foundTracks,
                    offset: self.normalizedOffsetInput(),
                    settings: self.xlsxSettings
                )
                try data.write(to: url, options: .atomic)
                self.statusText = "XLSX exported: \(url.lastPathComponent)"
            } catch {
                self.statusText = error.localizedDescription
            }
        }
    }

    func defaultXLSXName() -> String {
        let base = sessionName.isEmpty ? "Music_EDL" : sessionName
        let safe = base
            .replacingOccurrences(of: #"[^\w.-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return "\(safe.isEmpty ? "Music_EDL" : safe)_music-edl.xlsx"
    }
}









extension View {
    
}
