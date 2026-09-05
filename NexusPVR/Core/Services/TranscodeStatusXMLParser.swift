//
//  TranscodeStatusXMLParser.swift
//  PVR Client
//
//  Parses the raw XML document returned by NextPVR's
//  `channel.transcode.status` method.
//

import Foundation

/// Extracts progress from a `channel.transcode.status` response:
///
/// ```xml
/// <rsp stat="ok">
///   <percentage>100</percentage>
///   <final>false</final>
/// </rsp>
/// ```
///
/// `percentage` counts up to 100 as the server spins up ffmpeg and fills the
/// first HLS segments; the stream is only playable at 100. `final` means the
/// server has stopped making progress, so a `final` document short of 100 is
/// a failed transcode, not a slow one — the same reading Kodi's
/// `TranscodedBuffer::TranscodeStatus` applies.
nonisolated final class TranscodeStatusXMLParser: NSObject, XMLParserDelegate {
    private(set) var percentage: Int?
    private(set) var isFinal: Bool?

    private var currentText = ""

    /// Returns false when the document is not well-formed. Fields that are
    /// absent stay nil.
    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "percentage":
            percentage = Int(value)
        case "final":
            isFinal = (value as NSString).boolValue
        default:
            break
        }
        currentText = ""
    }
}
