import Foundation

struct MusicEDLEntry: Identifiable, Hashable {
    let id = UUID()
    var trackName: String
    var channel: Int?
    var event: String
    var clipName: String
    var startTime: String
    var endTime: String
    var duration: String
    var sourceFile: String
    var rawLine: String
    var order: Int
}

struct MusicEDLParseResult {
    let entries: [MusicEDLEntry]
    let matchedTracks: [String]
    let mutedRegionCount: Int
    let frameRate: Int
}

enum MusicEDLParser {
    static func parse(_ sessionInfo: String, targetTracks: [String], offset: String = "00:00:00:00") -> MusicEDLParseResult {
        let canonicalTargets = Dictionary(uniqueKeysWithValues: targetTracks.map { ($0.normalizedTrackKey, $0) })
        var currentTrack: String?
        var headerColumns: [String]?
        var entries: [MusicEDLEntry] = []
        var matched = Set<String>()
        var mutedRegionCount = 0
        var order = 0
        let fps = sessionFrameRate(in: sessionInfo)
        let offsetSubframes = offsetSubframes(from: offset, fps: fps) ?? 0

        for rawLine in sessionInfo.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }

            if let trackName = trackNameHeader(in: line) {
                let normalized = trackName.normalizedTrackKey
                if let target = canonicalTargets[normalized] {
                    currentTrack = trackName
                    matched.insert(target)
                } else {
                    currentTrack = nil
                }
                headerColumns = nil
                continue
            }

            guard let track = currentTrack else {
                continue
            }

            let columns = splitColumns(line)
            if isHeader(columns) {
                headerColumns = columns
                continue
            }

            let parsed = entry(from: line, columns: columns, headerColumns: headerColumns, trackName: track, order: order)
            order += 1
            if parsed.skippedMutedRegion {
                mutedRegionCount += 1
            }
            if let entry = parsed.entry {
                entries.append(entry)
            }
        }

        entries = groupedEntries(keepingOneChannelPerTrack(entries), fps: fps)
        entries = mergedAcrossTracks(entries, fps: fps)
        entries = mergedTimelineConnectors(entries, fps: fps)

        entries.sort {
            if $0.startTime == $1.startTime {
                return $0.trackName.localizedStandardCompare($1.trackName) == .orderedAscending
            }
            return $0.startTime.localizedStandardCompare($1.startTime) == .orderedAscending
        }

        entries = renumberEvents(entries.map { formattedEntry($0, fps: fps, offsetSubframes: offsetSubframes) })

        let matchedInInputOrder = targetTracks.filter { matched.contains($0) }
        return MusicEDLParseResult(entries: entries, matchedTracks: matchedInInputOrder, mutedRegionCount: mutedRegionCount, frameRate: fps)
    }

    static func isOffsetSyntaxValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        return firstRegexCapture(pattern: #"^[+-]?(\d{1,3}:\d{2}:\d{2}[:;.]\d{2})$"#, in: trimmed) != nil
    }

    static func isTimecodeSyntaxValid(_ value: String) -> Bool {
        timecodeSubframes(value, fps: 25) != nil
    }

    static func displayDuration(from start: String, to end: String, fps: Int) -> String {
        durationBetween(start, end, fps: fps)
    }

    static func renumberEvents(_ entries: [MusicEDLEntry]) -> [MusicEDLEntry] {
        entries.enumerated().map { index, entry in
            var updated = entry
            updated.event = "\(index + 1)"
            return updated
        }
    }

    private static func trackNameHeader(in line: String) -> String? {
        let patterns = [
            #"(?i)^\s*track\s+name\s*[:=]\s*(.+?)\s*$"#,
            #"(?i)^\s*track\s+edl\s*[:=]\s*(.+?)\s*$"#,
            #"(?i)^\s*track\s*[:=]\s*(.+?)\s*$"#,
            #"(?i)^\s*piste\s*[:=]\s*(.+?)\s*$"#
        ]

        for pattern in patterns {
            if let match = firstRegexCapture(pattern: pattern, in: line) {
                return cleanTrackName(match)
            }
        }

        let tabParts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if tabParts.count >= 2 {
            let key = tabParts[0].replacingOccurrences(of: " ", with: "").lowercased()
            if key == "trackname" || key == "track" || key == "piste" {
                return cleanTrackName(tabParts[1])
            }
        }

        return nil
    }

    private static func cleanTrackName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^["']|["']$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t:-"))
    }

    private static func isHeader(_ columns: [String]) -> Bool {
        let joined = columns.joined(separator: " ").lowercased()
        guard joined.contains("clip") || joined.contains("name") else {
            return false
        }
        return joined.contains("start") && (joined.contains("end") || joined.contains("duration") || joined.contains("length"))
    }

    private static func entry(from line: String, columns: [String], headerColumns: [String]?, trackName: String, order: Int) -> (entry: MusicEDLEntry?, skippedMutedRegion: Bool) {
        if let headerColumns, columns.count >= 3 {
            let state = value(columns, headerColumns, matching: { $0 == "state" || $0.contains("clip state") || $0.contains("region state") }) ?? ""
            if isMutedRegionState(state) {
                return (nil, true)
            }

            let start = value(columns, headerColumns, matching: { $0.contains("start") && !$0.contains("source") && !$0.contains("src") }) ?? timecodes(in: line).first
            let end = value(columns, headerColumns, matching: { $0.contains("end") && !$0.contains("source") && !$0.contains("src") }) ?? timecodes(in: line).dropFirst().first
            guard let start, let end else {
                return (nil, false)
            }

            let rawClipName = value(columns, headerColumns, matching: { $0.contains("clip") && $0.contains("name") })
                ?? value(columns, headerColumns, matching: { $0 == "name" })
                ?? fallbackClipName(from: line)
            let duration = value(columns, headerColumns, matching: { $0.contains("duration") || $0.contains("length") }) ?? ""
            let sourceFile = sanitizedSourceFile(value(columns, headerColumns, matching: isSourceFileHeader) ?? "")
            let event = value(columns, headerColumns, matching: { $0.contains("event") || $0 == "#" || $0.contains("num") }) ?? ""
            let channel = value(columns, headerColumns, matching: { $0 == "channel" || $0 == "chan" }).flatMap(Int.init)
            let clipName = resolvedClipName(rawClipName, sourceFile: sourceFile)
            guard !clipName.isEmpty else {
                return (nil, false)
            }

            return (MusicEDLEntry(
                trackName: trackName,
                channel: channel,
                event: event,
                clipName: clipName,
                startTime: start,
                endTime: end,
                duration: duration,
                sourceFile: sourceFile,
                rawLine: line,
                order: order
            ), false)
        }

        let times = timecodes(in: line)
        guard times.count >= 2 else {
            return (nil, false)
        }

        if let lastColumn = columns.last, isMutedRegionState(lastColumn) {
            return (nil, true)
        }

        let sourceFile = sanitizedSourceFile(fallbackSourceFile(from: line))
        let rawClipName = fallbackClipName(from: line)
        let clipName = resolvedClipName(rawClipName, sourceFile: sourceFile)
        guard !clipName.isEmpty else {
            return (nil, false)
        }

        return (MusicEDLEntry(
            trackName: trackName,
            channel: columns.first.flatMap(Int.init),
            event: firstEventToken(in: line),
            clipName: clipName,
            startTime: times[0],
            endTime: times[1],
            duration: times.count > 2 ? times[2] : "",
            sourceFile: sourceFile,
            rawLine: line,
            order: order
        ), false)
    }

    private static func keepingOneChannelPerTrack(_ entries: [MusicEDLEntry]) -> [MusicEDLEntry] {
        var selectedChannelByTrack: [String: Int] = [:]
        for entry in entries.sorted(by: { $0.order < $1.order }) {
            if selectedChannelByTrack[entry.trackName] == nil, let channel = entry.channel {
                selectedChannelByTrack[entry.trackName] = channel
            }
        }

        return entries.filter { entry in
            guard let selected = selectedChannelByTrack[entry.trackName] else {
                return true
            }
            return entry.channel == selected
        }
    }

    private struct GroupAccumulator {
        var trackName: String
        var channel: Int?
        var event: String
        var clipName: String
        var pieceKey: String
        var startTime: String
        var endTime: String
        var sourceFile: String
        var rawLines: [String]
        var firstOrder: Int
        var lastOrder: Int
    }

    private struct CrossTrackAccumulator {
        var trackNames: [String]
        var channel: Int?
        var event: String
        var clipName: String
        var pieceKey: String
        var startTime: String
        var endTime: String
        var sourceFiles: [String]
        var rawLines: [String]
        var firstOrder: Int
    }

    private static func groupedEntries(_ entries: [MusicEDLEntry], fps: Int) -> [MusicEDLEntry] {
        let ordered = entries.sorted {
            if $0.trackName == $1.trackName {
                return $0.order < $1.order
            }
            return $0.trackName.localizedStandardCompare($1.trackName) == .orderedAscending
        }

        var result: [MusicEDLEntry] = []
        var current: GroupAccumulator?
        var pendingLeadingTransitions: [MusicEDLEntry] = []
        var pendingTransitionTrack: String?

        func flushCurrent() {
            guard let group = current else { return }
            result.append(MusicEDLEntry(
                trackName: group.trackName,
                channel: group.channel,
                event: group.event,
                clipName: group.clipName,
                startTime: group.startTime,
                endTime: group.endTime,
                duration: durationBetween(group.startTime, group.endTime, fps: fps),
                sourceFile: group.sourceFile,
                rawLine: group.rawLines.joined(separator: "\n"),
                order: group.firstOrder
            ))
            current = nil
        }

        func attachableLeadingTransitions(to entry: MusicEDLEntry) -> [MusicEDLEntry] {
            guard pendingTransitionTrack == entry.trackName,
                  let lastTransition = pendingLeadingTransitions.last,
                  isContiguous(nextStart: entry.startTime, currentEnd: lastTransition.endTime, fps: fps) else {
                pendingLeadingTransitions = []
                pendingTransitionTrack = nil
                return []
            }

            let transitions = pendingLeadingTransitions
            pendingLeadingTransitions = []
            pendingTransitionTrack = nil
            return transitions
        }

        for entry in ordered {
            if isTransitionClip(entry.clipName) {
                guard var group = current, group.trackName == entry.trackName else {
                    if pendingTransitionTrack != entry.trackName {
                        pendingLeadingTransitions = []
                    }
                    pendingTransitionTrack = entry.trackName
                    pendingLeadingTransitions.append(entry)
                    continue
                }
                if isContiguous(nextStart: entry.startTime, currentEnd: group.endTime, fps: fps) {
                    group.endTime = laterTime(group.endTime, entry.endTime, fps: fps)
                    group.rawLines.append(entry.rawLine)
                    group.lastOrder = entry.order
                    current = group
                } else {
                    flushCurrent()
                    pendingTransitionTrack = entry.trackName
                    pendingLeadingTransitions = [entry]
                }
                continue
            }

            let key = pieceKey(for: entry.clipName)
            let displayName = displayPieceName(for: entry.clipName)
            if var group = current,
               group.trackName == entry.trackName,
               group.pieceKey == key,
               isContiguous(nextStart: entry.startTime, currentEnd: group.endTime, fps: fps) {
                group.endTime = laterTime(group.endTime, entry.endTime, fps: fps)
                group.sourceFile = group.sourceFile.isEmpty ? entry.sourceFile : group.sourceFile
                group.rawLines.append(entry.rawLine)
                group.lastOrder = entry.order
                current = group
            } else {
                flushCurrent()
                let leadingTransitions = attachableLeadingTransitions(to: entry)
                let leadingRawLines = leadingTransitions.map(\.rawLine)
                let startTime = leadingTransitions.first?.startTime ?? entry.startTime
                let endTime = leadingTransitions.reduce(entry.endTime) { partialEnd, transition in
                    laterTime(partialEnd, transition.endTime, fps: fps)
                }
                current = GroupAccumulator(
                    trackName: entry.trackName,
                    channel: entry.channel,
                    event: entry.event,
                    clipName: displayName,
                    pieceKey: key,
                    startTime: startTime,
                    endTime: endTime,
                    sourceFile: entry.sourceFile,
                    rawLines: leadingRawLines + [entry.rawLine],
                    firstOrder: leadingTransitions.first?.order ?? entry.order,
                    lastOrder: entry.order
                )
            }
        }

        flushCurrent()
        return result
    }

    private static func mergedAcrossTracks(_ entries: [MusicEDLEntry], fps: Int) -> [MusicEDLEntry] {
        let ordered = entries.sorted {
            let lhsKey = pieceKey(for: $0.clipName)
            let rhsKey = pieceKey(for: $1.clipName)
            if lhsKey != rhsKey {
                return lhsKey.localizedStandardCompare(rhsKey) == .orderedAscending
            }
            if $0.startTime != $1.startTime {
                return $0.startTime.localizedStandardCompare($1.startTime) == .orderedAscending
            }
            return $0.order < $1.order
        }

        var result: [MusicEDLEntry] = []
        var current: CrossTrackAccumulator?

        func flushCurrent() {
            guard let group = current else { return }
            result.append(MusicEDLEntry(
                trackName: group.trackNames.joined(separator: ", "),
                channel: group.channel,
                event: group.event,
                clipName: group.clipName,
                startTime: group.startTime,
                endTime: group.endTime,
                duration: durationBetween(group.startTime, group.endTime, fps: fps),
                sourceFile: group.sourceFiles.joined(separator: ", "),
                rawLine: group.rawLines.joined(separator: "\n"),
                order: group.firstOrder
            ))
            current = nil
        }

        for entry in ordered {
            let key = pieceKey(for: entry.clipName)
            if var group = current,
               group.pieceKey == key,
               isContiguous(nextStart: entry.startTime, currentEnd: group.endTime, fps: fps) {
                group.startTime = earlierTime(group.startTime, entry.startTime, fps: fps)
                group.endTime = laterTime(group.endTime, entry.endTime, fps: fps)
                group.trackNames = appendingUnique(entry.trackName, to: group.trackNames)
                group.sourceFiles = appendingUnique(entry.sourceFile, to: group.sourceFiles)
                group.rawLines.append(entry.rawLine)
                group.firstOrder = min(group.firstOrder, entry.order)
                current = group
            } else {
                flushCurrent()
                current = CrossTrackAccumulator(
                    trackNames: [entry.trackName],
                    channel: entry.channel,
                    event: entry.event,
                    clipName: entry.clipName,
                    pieceKey: key,
                    startTime: entry.startTime,
                    endTime: entry.endTime,
                    sourceFiles: entry.sourceFile.isEmpty ? [] : [entry.sourceFile],
                    rawLines: [entry.rawLine],
                    firstOrder: entry.order
                )
            }
        }

        flushCurrent()
        return result.map(sanitizedDisplayEntry)
    }

    private static func mergedTimelineConnectors(_ entries: [MusicEDLEntry], fps: Int) -> [MusicEDLEntry] {
        let ordered = entries.sorted {
            if $0.startTime != $1.startTime {
                return $0.startTime.localizedStandardCompare($1.startTime) == .orderedAscending
            }
            return $0.order < $1.order
        }

        var result: [MusicEDLEntry] = []
        var pendingConnectors: [MusicEDLEntry] = []

        func entryByAbsorbing(_ entry: MusicEDLEntry, into base: MusicEDLEntry, prependRaw: Bool = false) -> MusicEDLEntry {
            var updated = base
            updated.startTime = earlierTime(base.startTime, entry.startTime, fps: fps)
            updated.endTime = laterTime(base.endTime, entry.endTime, fps: fps)
            updated.duration = durationBetween(updated.startTime, updated.endTime, fps: fps)
            updated.sourceFile = preferredSourceFile(base.sourceFile, entry.sourceFile)
            updated.rawLine = prependRaw ? "\(entry.rawLine)\n\(base.rawLine)" : "\(base.rawLine)\n\(entry.rawLine)"
            updated.order = min(base.order, entry.order)
            return updated
        }

        func appendOrMerge(_ entry: MusicEDLEntry) {
            guard let last = result.last else {
                result.append(entry)
                return
            }

            if pieceKey(for: last.clipName) == pieceKey(for: entry.clipName),
               isContiguous(nextStart: entry.startTime, currentEnd: last.endTime, fps: fps) {
                var merged = entryByAbsorbing(entry, into: last)
                merged.clipName = last.clipName
                result[result.count - 1] = merged
            } else {
                result.append(entry)
            }
        }

        for entry in ordered {
            let sanitized = sanitizedDisplayEntry(entry)
            if isGenericMusicConnectorName(sanitized.clipName) {
                if let last = result.last,
                   isContiguous(nextStart: sanitized.startTime, currentEnd: last.endTime, fps: fps) {
                    result[result.count - 1] = entryByAbsorbing(sanitized, into: last)
                } else {
                    pendingConnectors.append(sanitized)
                }
                continue
            }

            var attached = sanitized
            if let firstPending = pendingConnectors.first,
               let lastPending = pendingConnectors.last,
               isContiguous(nextStart: attached.startTime, currentEnd: lastPending.endTime, fps: fps) {
                attached.startTime = firstPending.startTime
                attached.duration = durationBetween(attached.startTime, attached.endTime, fps: fps)
                attached.rawLine = (pendingConnectors.map(\.rawLine) + [attached.rawLine]).joined(separator: "\n")
                attached.order = min(attached.order, firstPending.order)
                pendingConnectors.removeAll()
            } else if !pendingConnectors.isEmpty {
                pendingConnectors.removeAll()
            }

            appendOrMerge(attached)
        }

        return result.map(sanitizedDisplayEntry)
    }

    private static func sessionFrameRate(in sessionInfo: String) -> Int {
        let patterns = [
            #"(?im)^\s*timecode\s+format\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)\s*(?:frame|fps)?\b"#,
            #"(?im)^\s*frame\s+rate\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)\b"#,
            #"(?im)\b([0-9]+(?:\.[0-9]+)?)\s*(?:fps|frame)\b"#
        ]

        for pattern in patterns {
            if let capture = firstRegexCapture(pattern: pattern, in: sessionInfo),
               let value = Double(capture) {
                let fps = Int(value.rounded())
                if fps > 0 {
                    return fps
                }
            }
        }

        return 25
    }

    private static func isTransitionClip(_ clipName: String) -> Bool {
        let normalized = clipName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.hasPrefix("(")
            && normalized.hasSuffix(")")
            && (normalized.contains("fade") || normalized.contains("cross"))
            || isGenericMusicConnectorName(clipName)
    }

    private static func isGenericMusicConnectorName(_ clipName: String) -> Bool {
        let folded = clipName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)\.[A-Za-z0-9]{2,5}$"#, with: "", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let withoutTakeSuffix = folded
            .replacingOccurrences(of: #"[\s._-]*\d{1,4}$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = withoutTakeSuffix
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .lowercased()

        return compact == "mu" || compact == "mus"
    }

    private static func pieceKey(for clipName: String) -> String {
        let displayed = displayPieceName(for: clipName)
        let folded = displayed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let key = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return key.isEmpty ? folded : key
    }

    private static func displayPieceName(for clipName: String) -> String {
        let original = clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = original
            .replacingOccurrences(of: #"(?i)\.(?:l|r|c|ls|rs|lfe|lss|rss|lc|rc)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for _ in 0..<4 {
            let stripped = name
                .replacingOccurrences(of: #"(?i)[._-](?:\d{1,4}|[a-z]\d{1,3})$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped == name {
                break
            }
            name = stripped
        }

        name = name
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t._-"))

        return name.isEmpty ? original : name
    }

    private static func resolvedClipName(_ clipName: String, sourceFile: String) -> String {
        let cleanedClipName = clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isGenericAudioProcessName(cleanedClipName) {
            if let sourceName = sourceNameForDisplay(sourceFile) {
                return sourceName
            }
            return ""
        }

        return cleanedClipName
    }

    private static func sanitizedDisplayEntry(_ entry: MusicEDLEntry) -> MusicEDLEntry {
        var updated = entry
        updated.sourceFile = sourceFileList(from: entry.sourceFile).joined(separator: ", ")
        return updated
    }

    private static func preferredSourceFile(_ lhs: String, _ rhs: String) -> String {
        let values = sourceFileList(from: lhs) + sourceFileList(from: rhs)
        return values.reduce(into: [String]()) { unique, value in
            if !unique.contains(value) {
                unique.append(value)
            }
        }.joined(separator: ", ")
    }

    private static func sourceFileList(from value: String) -> [String] {
        value
            .components(separatedBy: ",")
            .map(sanitizedSourceFile)
            .filter { !$0.isEmpty }
    }

    private static func sourceNameForDisplay(_ sourceFile: String) -> String? {
        let cleaned = sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isGenericAudioProcessName(cleaned) else {
            return nil
        }

        let filename = cleaned
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? cleaned
        let stem = filename.replacingOccurrences(of: #"\.[A-Za-z0-9]{2,5}$"#, with: "", options: .regularExpression)
        let displayed = displayPieceName(for: stem)
        return displayed.isEmpty || isGenericAudioProcessName(displayed) ? nil : displayed
    }

    private static func sanitizedSourceFile(_ sourceFile: String) -> String {
        let cleaned = sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        return isGenericAudioProcessName(cleaned) ? "" : cleaned
    }

    private static func isGenericAudioProcessName(_ value: String) -> Bool {
        let normalized = value
            .replacingOccurrences(of: #"\.[A-Za-z0-9]{2,5}$"#, with: "", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .lowercased()
        return normalized == "audioprocessstream" || normalized.hasPrefix("audioprocessstream")
    }

    private static func formattedEntry(_ entry: MusicEDLEntry, fps: Int, offsetSubframes: Int64) -> MusicEDLEntry {
        let startTime = formattedTimecode(entry.startTime, fps: fps, offsetSubframes: offsetSubframes)
        let endTime = formattedTimecode(entry.endTime, fps: fps, offsetSubframes: offsetSubframes)
        return MusicEDLEntry(
            trackName: entry.trackName,
            channel: entry.channel,
            event: entry.event,
            clipName: entry.clipName,
            startTime: startTime,
            endTime: endTime,
            duration: durationBetween(startTime, endTime, fps: fps),
            sourceFile: entry.sourceFile,
            rawLine: entry.rawLine,
            order: entry.order
        )
    }

    private static func formattedTimecode(_ value: String, fps: Int, offsetSubframes: Int64) -> String {
        guard let subframes = timecodeSubframes(value, fps: fps) else {
            return timecodeWithoutSubframes(value)
        }
        return formatTimecodeSubframes(max(0, subframes + offsetSubframes), fps: fps)
    }

    private static func offsetSubframes(from value: String, fps: Int) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }
        guard isOffsetSyntaxValid(trimmed) else {
            return nil
        }

        let sign: Int64 = trimmed.hasPrefix("-") ? -1 : 1
        var unsigned = trimmed
        if unsigned.hasPrefix("-") || unsigned.hasPrefix("+") {
            unsigned.removeFirst()
        }
        guard let subframes = timecodeSubframes(unsigned, fps: fps) else {
            return nil
        }
        return sign * subframes
    }

    private static func durationBetween(_ start: String, _ end: String, fps: Int) -> String {
        guard let startSubframes = timecodeSubframes(start, fps: fps),
              let endSubframes = timecodeSubframes(end, fps: fps) else {
            return ""
        }
        return formatDurationSubframes(max(0, endSubframes - startSubframes), fps: fps)
    }

    private static func isContiguous(nextStart: String, currentEnd: String, fps: Int) -> Bool {
        guard let nextStartSubframes = timecodeSubframes(nextStart, fps: fps),
              let currentEndSubframes = timecodeSubframes(currentEnd, fps: fps) else {
            return nextStart == currentEnd
        }

        let tolerance = Int64(2 * subframesPerFrame)
        return nextStartSubframes <= currentEndSubframes + tolerance
    }

    private static func laterTime(_ lhs: String, _ rhs: String, fps: Int) -> String {
        guard let lhsSubframes = timecodeSubframes(lhs, fps: fps),
              let rhsSubframes = timecodeSubframes(rhs, fps: fps) else {
            return lhs.localizedStandardCompare(rhs) == .orderedDescending ? lhs : rhs
        }
        return lhsSubframes >= rhsSubframes ? lhs : rhs
    }

    private static func earlierTime(_ lhs: String, _ rhs: String, fps: Int) -> String {
        guard let lhsSubframes = timecodeSubframes(lhs, fps: fps),
              let rhsSubframes = timecodeSubframes(rhs, fps: fps) else {
            return lhs.localizedStandardCompare(rhs) == .orderedAscending ? lhs : rhs
        }
        return lhsSubframes <= rhsSubframes ? lhs : rhs
    }

    private static func appendingUnique(_ value: String, to values: [String]) -> [String] {
        guard !value.isEmpty, !values.contains(value) else {
            return values
        }
        return values + [value]
    }

    private static let subframesPerFrame: Int64 = 100

    private static func timecodeSubframes(_ value: String, fps: Int) -> Int64? {
        guard let captures = regexCaptures(pattern: #"^\s*(\d{1,3}):(\d{2}):(\d{2})[:;.](\d{2})(?:\.(\d{1,3}))?\s*$"#, in: value),
              captures.count >= 4,
              let hours = Int64(captures[0]),
              let minutes = Int64(captures[1]),
              let seconds = Int64(captures[2]),
              let frames = Int64(captures[3]) else {
            return nil
        }

        let subframes = captures.count > 4 ? (Int64(captures[4]) ?? 0) : 0
        let safeFPS = max(fps, 1)
        let totalSeconds = (hours * 3600) + (minutes * 60) + seconds
        return ((totalSeconds * Int64(safeFPS) + frames) * subframesPerFrame) + subframes
    }

    private static func formatDurationSubframes(_ subframes: Int64, fps: Int) -> String {
        formatTimecodeSubframes(subframes, fps: fps)
    }

    private static func formatTimecodeSubframes(_ subframes: Int64, fps: Int) -> String {
        let safeFPS = Int64(max(fps, 1))
        let totalFrames = subframes / subframesPerFrame
        let totalSeconds = totalFrames / safeFPS
        let frames = totalFrames % safeFPS
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02lld:%02lld:%02lld:%02lld", hours, minutes, seconds, frames)
    }

    private static func timecodeWithoutSubframes(_ value: String) -> String {
        value.replacingOccurrences(of: #"(\d{1,3}:\d{2}:\d{2}[:;.]\d{2})(?:\.\d+)"#, with: "$1", options: .regularExpression)
    }

    private static func isMutedRegionState(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return normalized == "muted" || normalized == "clipmuted" || normalized == "regionmuted"
    }

    private static func value(_ columns: [String], _ headerColumns: [String], matching predicate: (String) -> Bool) -> String? {
        guard let index = headerColumns.firstIndex(where: { predicate(normalizedHeader($0)) }), index < columns.count else {
            return nil
        }
        let value = columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSourceFileHeader(_ value: String) -> Bool {
        (value.contains("file") || value.contains("source"))
            && !value.contains("start")
            && !value.contains("end")
            && !value.contains("duration")
            && !value.contains("length")
            && !value.contains("time")
            && !value.contains("clip")
            && !value.contains("region")
    }

    private static func splitColumns(_ line: String) -> [String] {
        if line.contains("\t") {
            return line.components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return line.components(separatedBy: twoOrMoreSpacesRegex)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let twoOrMoreSpacesRegex = try! NSRegularExpression(pattern: #"\s{2,}"#)

    private static func timecodes(in line: String) -> [String] {
        matches(pattern: #"\b\d{1,3}:\d{2}:\d{2}[:;.]\d{2}(?:\.\d+)?\b"#, in: line)
    }

    private static func firstEventToken(in line: String) -> String {
        let columns = splitColumns(line)
        return columns.first(where: { Int($0) != nil }) ?? ""
    }

    private static func fallbackClipName(from line: String) -> String {
        let scrubbed = line
            .replacingOccurrences(of: #"\b\d{1,3}:\d{2}:\d{2}[:;.]\d{2}(?:\.\d+)?\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = scrubbed.components(separatedBy: " ").filter { Int($0) == nil }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackSourceFile(from line: String) -> String {
        firstRegexCapture(pattern: #"([^\s\t]+\.(?:wav|aif|aiff|mp3|m4a|caf|mov|mp4))\b"#, in: line, options: [.caseInsensitive]) ?? ""
    }

    private static func firstRegexCapture(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func regexCaptures(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).map { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: text) else {
                return ""
            }
            return String(text[range])
        }
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }
}

private extension String {
    var normalizedTrackKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let fullRange = NSRange(startIndex..<endIndex, in: self)
        var result: [String] = []
        var cursor = startIndex

        regex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match, let range = Range(match.range, in: self) else {
                return
            }
            result.append(String(self[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }

        result.append(String(self[cursor..<endIndex]))
        return result
    }
}
