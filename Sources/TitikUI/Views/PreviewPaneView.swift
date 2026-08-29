import SwiftUI
import AppKit
import PDFKit
import AVFoundation
import UniformTypeIdentifiers
import TitikCore

public struct PreviewPaneView: View {
    public let item: SearchItem?

    public init(item: SearchItem?) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = item {
                // Header
                headerView(for: item)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Detail Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        previewContentView(for: item)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusable(false)

                Spacer(minLength: 0)
            } else {
                // Empty selection placeholder
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textMuted.opacity(0.5))
                    Text("Select an item to view preview")
                        .font(Theme.fontPreviewBody)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.15))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .focusable(false)
    }

    // MARK: - Header
    @ViewBuilder
    private func headerView(for item: SearchItem) -> some View {
        HStack(spacing: 12) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.colorForCategory(item.category).opacity(0.2))
                    Image(systemName: iconName(for: item))
                        .font(.system(size: 20))
                        .foregroundColor(Theme.colorForCategory(item.category))
                }
                .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Theme.fontPreviewTitle)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)

                Text(item.category.badgeName)
                    .font(Theme.fontPreviewSubtitle)
                    .foregroundColor(Theme.colorForCategory(item.category))
            }
        }
    }

    // MARK: - Routing
    @ViewBuilder
    private func previewContentView(for item: SearchItem) -> some View {
        switch item.previewType {
        case .image(let url):
            imagePreviewView(url: url)
        case .pdf(let url):
            pdfPreviewView(url: url)
        case .video(let url):
            videoPreviewView(url: url)
        case .audio(let url):
            audioPreviewView(url: url)
        case .code(let url, let lang):
            codeOrTextPreviewView(url: url, language: lang)
        case .text(let url):
            codeOrTextPreviewView(url: url, language: nil)
        case .directory(let url, let itemCount):
            directoryPreviewView(url: url, itemCount: itemCount)
        case .fileMetadata(let url):
            fileMetadataPreviewView(url: url)
        case .custom(let detail):
            genericDetailView(detail: detail)
        case .none:
            switch item.category {
            case .calculator:
                calculatorDetailView(item)
            case .clipboard:
                clipboardDetailView(item)
            case .application:
                applicationDetailView(item)
            case .systemCommand:
                systemCommandDetailView(item)
            case .file:
                if let url = resolveFileURL(for: item) {
                    fileMetadataPreviewView(url: url)
                } else {
                    genericDetailView(detail: item.previewDetail ?? item.actionPayload)
                }
            case .plugin, .custom, .directory, .emoji:
                genericDetailView(detail: item.previewDetail ?? item.actionPayload)
            }
        }
    }

    // MARK: - Rich Previews

    private func imagePreviewView(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let nsImage = NSImage(contentsOf: url) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                metadataRow(label: "Dimensions", value: "\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
            }

            if let size = fileSizeString(for: url) {
                metadataRow(label: "File Size", value: size)
            }
            if let modDate = modDateString(for: url) {
                metadataRow(label: "Modified", value: modDate)
            }
            metadataRow(label: "Path", value: url.path)
        }
    }

    private func pdfPreviewView(url: URL) -> some View {
        PDFPreviewContentView(url: url)
    }

    private func videoPreviewView(url: URL) -> some View {
        VideoPreviewContentView(url: url)
    }

    private func audioPreviewView(url: URL) -> some View {
        AudioPreviewContentView(url: url)
    }

    private func codeOrTextPreviewView(url: URL, language: String?) -> some View {
        CodeOrTextPreviewContentView(url: url, language: language)
    }

    private func directoryPreviewView(url: URL, itemCount: Int) -> some View {
        let childItems = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let previewChildren = Array(childItems.prefix(8))

        return VStack(alignment: .leading, spacing: 10) {
            metadataRow(label: "Path", value: url.path)

            if let modDate = modDateString(for: url) {
                metadataRow(label: "Modified", value: modDate)
            }

            metadataRow(label: "Contents", value: "\(itemCount) items in folder")

            if !previewChildren.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(previewChildren, id: \.path) { child in
                        HStack(spacing: 6) {
                            var isDir: ObjCBool = false
                            let _ = FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir)
                            Image(systemName: isDir.boolValue ? "folder.fill" : "doc.fill")
                                .font(.system(size: 11))
                                .foregroundColor(isDir.boolValue ? Theme.categoryDirectory : Theme.textMuted)

                            Text(child.lastPathComponent)
                                .font(Theme.fontPreviewBody)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 1)
                    }

                    if childItems.count > 8 {
                        Text("+ \(childItems.count - 8) more...")
                            .font(Theme.fontPreviewSubtitle)
                            .foregroundColor(Theme.textMuted)
                            .padding(.top, 2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    private func fileMetadataPreviewView(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header banner card
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileTypeDescription(for: url))
                        .font(Theme.fontPreviewTitle)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    if let uti = fileUTIString(for: url) {
                        Text(uti)
                            .font(Theme.fontCode)
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            metadataRow(label: "Path", value: url.path)

            if let size = fileDetailedSize(for: url) {
                metadataRow(label: "File Size", value: size)
            }

            if let modDate = modDateString(for: url) {
                metadataRow(label: "Modified", value: modDate)
            }

            if let createDate = creationDateString(for: url) {
                metadataRow(label: "Created", value: createDate)
            }

            if let perms = filePermissionsString(for: url) {
                metadataRow(label: "Permissions", value: perms)
            }
        }
    }

    // MARK: - Category Defaults

    private func calculatorDetailView(_ item: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Result")
                .font(Theme.fontPreviewSubtitle)
                .foregroundColor(Theme.textMuted)

            Text(item.title)
                .font(Theme.fontMathResult)
                .foregroundColor(Theme.categoryMath)
                .textSelection(.enabled)

            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(Theme.fontPreviewBody)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private func clipboardDetailView(_ item: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard Content")
                .font(Theme.fontPreviewSubtitle)
                .foregroundColor(Theme.textMuted)

            Text(item.previewDetail ?? item.actionPayload)
                .font(Theme.fontCode)
                .foregroundColor(Theme.textSecondary)
                .textSelection(.enabled)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        }
    }

    private func applicationDetailView(_ item: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow(label: "Path", value: item.actionPayload)
        }
    }

    private func systemCommandDetailView(_ item: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.subtitle)
                .font(Theme.fontPreviewBody)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func genericDetailView(detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail)
                .font(Theme.fontPreviewBody)
                .foregroundColor(Theme.textSecondary)
        }
    }

    fileprivate func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.fontPreviewSubtitle)
                .foregroundColor(Theme.textMuted)
            Text(value)
                .font(Theme.fontCode)
                .foregroundColor(Theme.textSecondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Helpers

    private func iconName(for item: SearchItem) -> String {
        switch item.category {
        case .application: return "app.badge"
        case .systemCommand: return "gearshape.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .calculator: return "function"
        case .plugin: return "puzzlepiece.extension.fill"
        case .custom: return "star.fill"
        case .directory: return "folder.fill"
        case .emoji: return "face.smiling"
        case .file:
            switch item.previewType {
            case .image: return "photo.fill"
            case .video: return "film.fill"
            case .audio: return "music.note"
            case .pdf: return "doc.richtext.fill"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .fileMetadata: return "doc.fill"
            default: return "doc.fill"
            }
        }
    }

    private func resolveFileURL(for item: SearchItem) -> URL? {
        if let previewURL = item.previewURL {
            return previewURL
        }
        if !item.actionPayload.isEmpty {
            if item.actionPayload.hasPrefix("/") {
                return URL(fileURLWithPath: item.actionPayload)
            }
            if let parsed = URL(string: item.actionPayload), parsed.scheme != nil {
                return parsed
            }
        }
        return nil
    }

    private func fileSizeString(for url: URL) -> String? {
        guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = resources.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func modDateString(for url: URL) -> String? {
        guard let resources = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = resources.contentModificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func creationDateString(for url: URL) -> String? {
        guard let resources = try? url.resourceValues(forKeys: [.creationDateKey]),
              let date = resources.creationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func fileTypeDescription(for url: URL) -> String {
        let ext = url.pathExtension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            if let desc = utType.localizedDescription, !desc.isEmpty {
                return desc
            }
            return utType.preferredFilenameExtension?.uppercased() ?? ext.uppercased()
        }
        if !ext.isEmpty {
            return "\(ext.uppercased()) Document"
        }
        return "Document"
    }

    private func fileUTIString(for url: URL) -> String? {
        let ext = url.pathExtension
        guard !ext.isEmpty, let utType = UTType(filenameExtension: ext) else {
            return nil
        }
        return utType.identifier
    }

    private func fileDetailedSize(for url: URL) -> String? {
        guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = resources.fileSize else { return nil }
        let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        let exactBytes = formatNumber(size)
        return "\(formattedSize) (\(exactBytes) byte\(size == 1 ? "" : "s"))"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func filePermissionsString(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let posixPerms = attrs[.posixPermissions] as? Int
        let owner = attrs[.ownerAccountName] as? String

        var parts: [String] = []
        if let perms = posixPerms {
            let permStr = formatPosixPermissions(perms)
            let octalStr = String(format: "%04o", perms)
            parts.append("\(permStr) (\(octalStr))")
        }

        if let owner = owner, !owner.isEmpty {
            parts.append(owner)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    private func formatPosixPermissions(_ permissions: Int) -> String {
        let r1 = (permissions & 0o400) != 0 ? "r" : "-"
        let w1 = (permissions & 0o200) != 0 ? "w" : "-"
        let x1 = (permissions & 0o100) != 0 ? "x" : "-"

        let r2 = (permissions & 0o040) != 0 ? "r" : "-"
        let w2 = (permissions & 0o020) != 0 ? "w" : "-"
        let x2 = (permissions & 0o010) != 0 ? "x" : "-"

        let r3 = (permissions & 0o004) != 0 ? "r" : "-"
        let w3 = (permissions & 0o002) != 0 ? "w" : "-"
        let x3 = (permissions & 0o001) != 0 ? "x" : "-"

        return "\(r1)\(w1)\(x1)\(r2)\(w2)\(x2)\(r3)\(w3)\(x3)"
    }

    fileprivate func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else { return "0:00" }
        let totalSecs = Int(seconds)
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        let hrs = mins / 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins % 60, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
}

// MARK: - Asynchronous Preview Subviews

private struct PDFPreviewContentView: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var pageCount: Int?
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thumb = thumbnail {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .frame(height: 140)
            }

            if let count = pageCount {
                metadataRow(label: "Pages", value: "\(count) page\(count == 1 ? "" : "s")")
            }

            if let size = fileSizeString(for: url) {
                metadataRow(label: "File Size", value: size)
            }
            if let modDate = modDateString(for: url) {
                metadataRow(label: "Modified", value: modDate)
            }
            metadataRow(label: "Path", value: url.path)
        }
        .task(id: url) {
            isLoading = true
            thumbnail = nil
            pageCount = nil
            let loaded = await Task.detached(priority: .userInitiated) { () -> (CGImage?, Int)? in
                guard let doc = PDFDocument(url: url) else { return nil }
                let count = doc.pageCount
                let cgThumb = doc.page(at: 0)?
                    .thumbnail(of: CGSize(width: 240, height: 180), for: .mediaBox)
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
                return (cgThumb, count)
            }.value

            if let (cgThumb, count) = loaded {
                if let cg = cgThumb {
                    self.thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
                self.pageCount = count
            }
            self.isLoading = false
        }
    }
}

private struct AudioPreviewContentView: View {
    let url: URL
    @State private var durationSeconds: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.categoryFile)
                    Text(url.lastPathComponent)
                        .font(Theme.fontPreviewSubtitle)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(16)
            }
            .frame(height: 110)

            if let durationSecs = durationSeconds, !durationSecs.isNaN, durationSecs > 0 {
                metadataRow(label: "Duration", value: formatDuration(durationSecs))
            }
            metadataRow(label: "Format", value: url.pathExtension.uppercased())
            if let size = fileSizeString(for: url) {
                metadataRow(label: "File Size", value: size)
            }
            metadataRow(label: "Path", value: url.path)
        }
        .task(id: url) {
            durationSeconds = nil
            let asset = AVAsset(url: url)
            if let cmDuration = try? await asset.load(.duration) {
                durationSeconds = CMTimeGetSeconds(cmDuration)
            }
        }
    }
}

private struct VideoPreviewContentView: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var durationSeconds: Double?
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thumb = thumbnail {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .frame(height: 140)
            }

            if let durationSecs = durationSeconds, !durationSecs.isNaN, durationSecs > 0 {
                metadataRow(label: "Duration", value: formatDuration(durationSecs))
            }
            metadataRow(label: "Format", value: url.pathExtension.uppercased())
            if let size = fileSizeString(for: url) {
                metadataRow(label: "File Size", value: size)
            }
            metadataRow(label: "Path", value: url.path)
        }
        .task(id: url) {
            isLoading = true
            thumbnail = nil
            durationSeconds = nil
            let loaded = await Task.detached(priority: .userInitiated) { () -> (CGImage?, Double)? in
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                let cgImage = try? generator.copyCGImage(at: time, actualTime: nil)
                let duration: Double
                if let cmDuration = try? await asset.load(.duration) {
                    duration = CMTimeGetSeconds(cmDuration)
                } else {
                    duration = .nan
                }
                return (cgImage, duration)
            }.value

            if let (cgThumb, duration) = loaded {
                if let cg = cgThumb {
                    self.thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
                self.durationSeconds = duration
            }
            self.isLoading = false
        }
    }
}

private struct CodeOrTextPreviewContentView: View {
    let url: URL
    let language: String?
    @State private var content: String = ""
    @State private var totalLines: Int = 0
    @State private var charCount: Int = 0
    @State private var isLoading: Bool = true

    var body: some View {
        let lines = content.components(separatedBy: .newlines)
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .frame(height: 140)
            } else {
                // Stats bar
                HStack(spacing: 8) {
                    if let lang = language ?? (url.pathExtension.isEmpty ? nil : url.pathExtension) {
                        Text(lang.uppercased())
                            .font(Theme.fontBadge)
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Theme.accent.opacity(0.15))
                            )
                    }

                    Text("\(totalLines) lines")
                        .font(Theme.fontPreviewSubtitle)
                        .foregroundColor(Theme.textMuted)

                    Text("•")
                        .foregroundColor(Theme.textMuted.opacity(0.5))

                    Text("\(charCount) chars")
                        .font(Theme.fontPreviewSubtitle)
                        .foregroundColor(Theme.textMuted)

                    Spacer()
                }

                // Code box
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        // Line numbers
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(1...max(1, lines.count), id: \.self) { lineNum in
                                Text("\(lineNum)")
                                    .font(Theme.fontCode)
                                    .foregroundColor(Theme.textMuted.opacity(0.4))
                            }
                        }

                        // Content
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<lines.count, id: \.self) { i in
                                Text(lines[i].isEmpty ? " " : lines[i])
                                    .font(Theme.fontCode)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(8)
                }
                .focusable(false)
                .frame(maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                metadataRow(label: "Path", value: url.path)
            }
        }
        .task(id: url) {
            isLoading = true
            content = ""
            totalLines = 0
            charCount = 0
            let loaded = await Task.detached(priority: .userInitiated) { () -> (String, Int, Int) in
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      let string = String(data: data.prefix(100_000), encoding: .utf8) ?? String(data: data.prefix(100_000), encoding: .ascii) else {
                    return ("", 0, 0)
                }
                let allLines = string.components(separatedBy: .newlines)
                let preview = allLines.prefix(200).joined(separator: "\n")
                return (preview, allLines.count, string.count)
            }.value

            self.content = loaded.0
            self.totalLines = loaded.1
            self.charCount = loaded.2
            self.isLoading = false
        }
    }
}

// MARK: - File-Private Shared Helpers

fileprivate func metadataRow(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label)
            .font(Theme.fontPreviewSubtitle)
            .foregroundColor(Theme.textMuted)
        Text(value)
            .font(Theme.fontCode)
            .foregroundColor(Theme.textSecondary)
            .textSelection(.enabled)
    }
}

fileprivate func fileSizeString(for url: URL) -> String? {
    guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
          let size = resources.fileSize else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
}

fileprivate func modDateString(for url: URL) -> String? {
    guard let resources = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
          let date = resources.contentModificationDate else { return nil }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

fileprivate func formatDuration(_ seconds: Double) -> String {
    guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else { return "0:00" }
    let totalSecs = Int(seconds)
    let mins = totalSecs / 60
    let secs = totalSecs % 60
    let hrs = mins / 60
    if hrs > 0 {
        return String(format: "%d:%02d:%02d", hrs, mins % 60, secs)
    } else {
        return String(format: "%d:%02d", mins, secs)
    }
}
