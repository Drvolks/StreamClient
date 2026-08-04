//
//  StreamInfoXMLParser.swift
//  PVR Client
//
//  Parses the raw XML `<map>` document returned by NextPVR's
//  `channel.stream.info` method.
//

import Foundation

/// Extracts the timeshift buffer fields from a `channel.stream.info` response:
///
/// ```xml
/// <map>
///   <stream_duration>134000</stream_duration>
///   <stream_length>18874368</stream_length>
///   <complete>false</complete>
/// </map>
/// ```
///
/// Unlike the other service methods this one answers with raw XML even when
/// `format=json` is requested, so it can't share the JSON decoding path.
nonisolated final class StreamInfoXMLParser: NSObject, XMLParserDelegate {
    private(set) var streamDuration: Int64?
    private(set) var streamLength: Int64?
    private(set) var isComplete: Bool?

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
        case "stream_duration":
            streamDuration = Int64(value)
        case "stream_length":
            streamLength = Int64(value)
        case "complete":
            isComplete = (value as NSString).boolValue
        default:
            break
        }
        currentText = ""
    }
}
