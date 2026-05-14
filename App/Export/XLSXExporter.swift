import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct XLSXExportSettings {
    var headerFill: Color = AppTheme.backgroundTop
    var rowFillEven: Color = Color(hex: "FFFFFF")
    var rowFillOdd: Color = Color(hex: "F4F4F4")
}

enum XLSXExporter {
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

struct ZipArchive {
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

extension UTType {
    static let excelWorkbook = UTType(filenameExtension: "xlsx")!
}
