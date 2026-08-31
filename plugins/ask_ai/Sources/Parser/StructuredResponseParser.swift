import Foundation
import TitikPluginKit

public struct ParsedStreamOutput: Sendable, Equatable {
    public var textDeltas: [String]
    public var mediaAssets: [MediaAsset]
    public var citations: [CitationSource]
    public var rateLimitRetryAfter: TimeInterval?
    public var isDone: Bool

    public init(
        textDeltas: [String] = [],
        mediaAssets: [MediaAsset] = [],
        citations: [CitationSource] = [],
        rateLimitRetryAfter: TimeInterval? = nil,
        isDone: Bool = false
    ) {
        self.textDeltas = textDeltas
        self.mediaAssets = mediaAssets
        self.citations = citations
        self.rateLimitRetryAfter = rateLimitRetryAfter
        self.isDone = isDone
    }
}

public final class StructuredResponseParser: @unchecked Sendable {
    private var pendingBytes = Data()
    private var lineBuffer = ""
    private let lock = NSLock()

    private var knownCitations: [Int: CitationSource] = [:]
    private var knownMediaIds: Set<String> = []

    public init() {}

    // MARK: - UTF-8 Decoding with multibyte chunk split support

    public static func decodeValidUTF8Prefix(data: Data) -> (text: String, remainder: Data) {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return ("", Data()) }

        let count = bytes.count
        var i = count - 1
        var leadIndex: Int? = nil

        let maxBack = max(0, count - 4)
        while i >= maxBack {
            let byte = bytes[i]
            if (byte & 0x80) == 0 {
                // 1-byte ASCII, complete
                break
            } else if (byte & 0xC0) == 0xC0 {
                // Multi-byte leading byte
                leadIndex = i
                break
            }
            i -= 1
        }

        if let lead = leadIndex {
            let leadByte = bytes[lead]
            let neededBytes: Int
            if (leadByte & 0xE0) == 0xC0 {
                neededBytes = 2
            } else if (leadByte & 0xF0) == 0xE0 {
                neededBytes = 3
            } else if (leadByte & 0xF8) == 0xF0 {
                neededBytes = 4
            } else {
                neededBytes = 1
            }

            let availableBytes = count - lead
            if availableBytes < neededBytes {
                let validBytes = Array(bytes[0..<lead])
                let remainderBytes = Array(bytes[lead..<count])
                let str = String(bytes: validBytes, encoding: .utf8) ?? ""
                return (str, Data(remainderBytes))
            }
        }

        let str = String(bytes: bytes, encoding: .utf8) ?? ""
        return (str, Data())
    }

    // MARK: - Streaming Chunks Processing

    public func processChunk(_ data: Data) -> ParsedStreamOutput {
        lock.lock()
        defer { lock.unlock() }

        var output = ParsedStreamOutput()
        var combinedData = pendingBytes
        combinedData.append(data)

        let (decodedText, remainder) = Self.decodeValidUTF8Prefix(data: combinedData)
        pendingBytes = remainder

        lineBuffer += decodedText

        let lines = lineBuffer.components(separatedBy: "\n")
        if lines.count > 1 {
            // Keep the last partial line in lineBuffer
            lineBuffer = lines.last ?? ""

            // Process all complete lines
            for line in lines.dropLast() {
                let lineOutput = processLine(line)
                output.textDeltas.append(contentsOf: lineOutput.textDeltas)
                output.mediaAssets.append(contentsOf: lineOutput.mediaAssets)
                output.citations.append(contentsOf: lineOutput.citations)
                if let retry = lineOutput.rateLimitRetryAfter {
                    output.rateLimitRetryAfter = retry
                }
                if lineOutput.isDone {
                    output.isDone = true
                }
            }
        }

        return output
    }

    public func processStringChunk(_ text: String) -> ParsedStreamOutput {
        if let data = text.data(using: .utf8) {
            return processChunk(data)
        }
        return ParsedStreamOutput()
    }

    public func flush() -> ParsedStreamOutput {
        lock.lock()
        defer { lock.unlock() }

        var output = ParsedStreamOutput()
        if !lineBuffer.isEmpty {
            let lineOutput = processLine(lineBuffer)
            output.textDeltas.append(contentsOf: lineOutput.textDeltas)
            output.mediaAssets.append(contentsOf: lineOutput.mediaAssets)
            output.citations.append(contentsOf: lineOutput.citations)
            if let retry = lineOutput.rateLimitRetryAfter {
                output.rateLimitRetryAfter = retry
            }
            if lineOutput.isDone {
                output.isDone = true
            }
            lineBuffer = ""
        }
        pendingBytes = Data()
        return output
    }

    // MARK: - Line & SSE Processing

    private func processLine(_ rawLine: String) -> ParsedStreamOutput {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Ignore empty lines
        if trimmed.isEmpty {
            return ParsedStreamOutput()
        }

        // 2. Ignore SSE comments (e.g. ": ping", ": keep-alive")
        if trimmed.hasPrefix(":") {
            return ParsedStreamOutput()
        }

        var payload = trimmed
        if trimmed.hasPrefix("data: ") {
            payload = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("data:") {
            payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }

        // 3. Check for [DONE]
        if payload == "[DONE]" {
            return ParsedStreamOutput(isDone: true)
        }

        var output = ParsedStreamOutput()

        let lower = trimmed.lowercased()
        if lower == "not found" ||
           lower.hasPrefix("404") ||
           lower.contains("cannot post") ||
           lower.hasPrefix("<!doctype") ||
           lower.hasPrefix("<html") {
            output.textDeltas.append("Error: Server returned '\(trimmed)'")
            return output
        }

        // 4. Try parsing JSON payload (OpenCode, OpenAI, Antigravity format)
        if payload.hasPrefix("{") && payload.hasSuffix("}") {
            if let jsonData = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                // Check for rate limit error
                if let errorObj = json["error"] as? [String: Any] {
                    if let code = errorObj["code"] as? Int, code == 429 {
                        let retryAfter = (errorObj["retry_after"] as? Double) ?? 3.0
                        output.rateLimitRetryAfter = retryAfter
                        return output
                    }
                }

                // OpenAI Responses and Anthropic Messages use typed SSE
                // events instead of the Chat Completions `choices` shape.
                if let eventType = json["type"] as? String {
                    switch eventType {
                    case "response.output_text.delta":
                        if let delta = json["delta"] as? String {
                            appendText(delta, to: &output)
                        }
                    case "response.completed", "response.done", "message_stop":
                        output.isDone = true
                    case "content_block_delta":
                        if let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            appendText(text, to: &output)
                        }
                    default:
                        break
                    }
                }

                // Check for choices / delta text
                if let choices = json["choices"] as? [[String: Any]] {
                    for choice in choices {
                        if let delta = choice["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            let (cleanText, media, citations) = extractInlineTokens(from: content)
                            if !cleanText.isEmpty {
                                output.textDeltas.append(cleanText)
                            }
                            output.mediaAssets.append(contentsOf: media)
                            output.citations.append(contentsOf: citations)
                        } else if let text = choice["text"] as? String {
                            let (cleanText, media, citations) = extractInlineTokens(from: text)
                            if !cleanText.isEmpty {
                                output.textDeltas.append(cleanText)
                            }
                            output.mediaAssets.append(contentsOf: media)
                            output.citations.append(contentsOf: citations)
                        }
                    }
                }

                // Check for top-level message content
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    let (cleanText, media, citations) = extractInlineTokens(from: content)
                    if !cleanText.isEmpty {
                        output.textDeltas.append(cleanText)
                    }
                    output.mediaAssets.append(contentsOf: media)
                    output.citations.append(contentsOf: citations)
                }

                if let contentBlocks = json["content"] as? [[String: Any]] {
                    for block in contentBlocks {
                        if let text = block["text"] as? String {
                            appendText(text, to: &output)
                        }
                    }
                }

                // Non-streaming Responses fallbacks return text inside
                // output[]. Keep this path for gateways that ignore `stream`.
                if let outputItems = json["output"] as? [[String: Any]] {
                    for item in outputItems {
                        if let contentBlocks = item["content"] as? [[String: Any]] {
                            for block in contentBlocks {
                                if let text = block["text"] as? String {
                                    appendText(text, to: &output)
                                }
                            }
                        }
                    }
                }

                // Check for top-level citations
                if let citationsJson = json["citations"] as? [[String: Any]] {
                    for citeObj in citationsJson {
                        if let url = citeObj["url"] as? String ?? citeObj["urlString"] as? String {
                            let title = (citeObj["title"] as? String) ?? ""
                            let snippet = citeObj["snippet"] as? String
                            let favicon = citeObj["favicon"] as? String ?? citeObj["faviconURLString"] as? String
                            let index = (citeObj["index"] as? Int) ?? (knownCitations.count + 1)

                            let citation = CitationSource(
                                index: index,
                                title: title,
                                urlString: url,
                                snippet: snippet,
                                faviconURLString: favicon
                            )
                            if knownCitations[index] == nil {
                                knownCitations[index] = citation
                                output.citations.append(citation)
                            }
                        }
                    }
                }

                // Check for top-level media
                if let mediaJson = json["media"] as? [[String: Any]] ?? json["mediaAssets"] as? [[String: Any]] {
                    for mediaObj in mediaJson {
                        let typeStr = (mediaObj["type"] as? String) ?? "image"
                        let title = (mediaObj["title"] as? String) ?? "Media"
                        let url = mediaObj["url"] as? String ?? mediaObj["urlString"] as? String
                        let content = mediaObj["content"] as? String
                        let id = (mediaObj["id"] as? String) ?? UUID().uuidString
                        let type = MediaAssetType(rawValue: typeStr) ?? .image

                        if !knownMediaIds.contains(id) {
                            knownMediaIds.insert(id)
                            let asset = MediaAsset(
                                id: id,
                                type: type,
                                title: title,
                                urlString: url,
                                content: content
                            )
                            output.mediaAssets.append(asset)
                        }
                    }
                }

                return output
            }
        }

        // 5. Plain text or SSE text payload
        let (cleanText, media, citations) = extractInlineTokens(from: payload)
        if !cleanText.isEmpty {
            output.textDeltas.append(cleanText)
        }
        output.mediaAssets.append(contentsOf: media)
        output.citations.append(contentsOf: citations)

        return output
    }

    private func appendText(_ text: String, to output: inout ParsedStreamOutput) {
        let (cleanText, media, citations) = extractInlineTokens(from: text)
        if !cleanText.isEmpty {
            output.textDeltas.append(cleanText)
        }
        output.mediaAssets.append(contentsOf: media)
        output.citations.append(contentsOf: citations)
    }

    // MARK: - Inline Media & Citation Extraction

    public func extractInlineTokens(from text: String) -> (cleanedText: String, media: [MediaAsset], citations: [CitationSource]) {
        var currentText = text
        var extractedMedia: [MediaAsset] = []
        var extractedCitations: [CitationSource] = []

        // 1. Extract [[media:type:key=val&key=val...]]
        // Example: [[media:image:url=https://example.com/pic.png&title=Photo&alt=Sample]]
        let mediaRegex = try? NSRegularExpression(pattern: #"\[\[media:(image|diagram|map|code):(.*?)\]\]"#, options: [])
        if let regex = mediaRegex {
            let matches = regex.matches(in: currentText, options: [], range: NSRange(currentText.startIndex..<currentText.endIndex, in: currentText))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: currentText),
                      let typeRange = Range(match.range(at: 1), in: currentText),
                      let paramsRange = Range(match.range(at: 2), in: currentText) else {
                    continue
                }

                let typeStr = String(currentText[typeRange])
                let paramsStr = String(currentText[paramsRange])
                let params = parseURLQueryParameters(paramsStr)

                let mediaType: MediaAssetType
                switch typeStr {
                case "diagram": mediaType = .diagram
                case "map": mediaType = .map
                case "code": mediaType = .codeSnippet
                default: mediaType = .image
                }

                let title = params["title"] ?? (params["alt"] ?? "Media")
                let urlStr = params["url"] ?? params["urlString"]
                let content = params["content"]
                let lang = params["lang"] ?? params["language"]
                let lat = Double(params["lat"] ?? params["latitude"] ?? "")
                let lon = Double(params["lon"] ?? params["longitude"] ?? "")
                let alt = params["alt"] ?? params["altText"]

                let asset = MediaAsset(
                    type: mediaType,
                    title: title,
                    urlString: urlStr,
                    content: content,
                    language: lang,
                    latitude: lat,
                    longitude: lon,
                    altText: alt
                )

                extractedMedia.append(asset)
                currentText.removeSubrange(fullRange)
            }
        }

        // 2. Extract [[cite:index=1&url=https://...&title=...]]
        let citeTokenRegex = try? NSRegularExpression(pattern: #"\[\[cite:(.*?)\]\]"#, options: [])
        if let regex = citeTokenRegex {
            let matches = regex.matches(in: currentText, options: [], range: NSRange(currentText.startIndex..<currentText.endIndex, in: currentText))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: currentText),
                      let paramsRange = Range(match.range(at: 1), in: currentText) else {
                    continue
                }

                let paramsStr = String(currentText[paramsRange])
                let params = parseURLQueryParameters(paramsStr)

                let index = Int(params["index"] ?? "") ?? (knownCitations.count + 1)
                let title = params["title"] ?? (params["domain"] ?? "Source")
                let url = params["url"] ?? params["urlString"] ?? ""
                let snippet = params["snippet"]
                let fav = params["favicon"] ?? params["faviconURLString"]

                if !url.isEmpty {
                    let cite = CitationSource(
                        index: index,
                        title: title,
                        urlString: url,
                        snippet: snippet,
                        faviconURLString: fav
                    )
                    extractedCitations.append(cite)
                    knownCitations[index] = cite
                }

                // Replace inline token with readable footnote badge [1]
                currentText.replaceSubrange(fullRange, with: " [\(index)] ")
            }
        }

        // 3. Extract footnote definitions: [1]: https://example.com "Title"
        let footnoteDefRegex = try? NSRegularExpression(pattern: #"(?m)^\[\^?(\d+)\]:\s*(https?://[^\s]+)(?:\s+"([^"]+)")?"#, options: [])
        if let regex = footnoteDefRegex {
            let matches = regex.matches(in: currentText, options: [], range: NSRange(currentText.startIndex..<currentText.endIndex, in: currentText))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: currentText),
                      let indexRange = Range(match.range(at: 1), in: currentText),
                      let urlRange = Range(match.range(at: 2), in: currentText) else {
                    continue
                }

                let index = Int(currentText[indexRange]) ?? (knownCitations.count + 1)
                let url = String(currentText[urlRange])
                var title = ""
                if match.numberOfRanges > 3, let titleRange = Range(match.range(at: 3), in: currentText) {
                    title = String(currentText[titleRange])
                }

                let cite = CitationSource(
                    index: index,
                    title: title.isEmpty ? "Source \(index)" : title,
                    urlString: url
                )
                extractedCitations.append(cite)
                knownCitations[index] = cite

                // Remove footnote definition line from main body text
                currentText.removeSubrange(fullRange)
            }
        }

        return (currentText, extractedMedia, extractedCitations)
    }

    private func parseURLQueryParameters(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = query.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces)
                let rawVal = kv.dropFirst().joined(separator: "=").replacingOccurrences(of: "+", with: " ")
                let val = rawVal.removingPercentEncoding ?? rawVal
                result[key] = val
            } else if kv.count == 1 && !kv[0].isEmpty {
                result[kv[0]] = ""
            }
        }
        return result
    }
}
