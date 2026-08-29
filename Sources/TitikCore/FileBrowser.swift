import Foundation
import AppKit

public struct DirectoryNavigationSession: Sendable, Equatable {
    public let rootQueryPrefix: String
    public let rootURL: URL
    public var currentDirectoryURL: URL

    public init(rootQueryPrefix: String, rootURL: URL, currentDirectoryURL: URL? = nil) {
        self.rootQueryPrefix = rootQueryPrefix.hasSuffix("/") ? rootQueryPrefix : (rootQueryPrefix + "/")
        self.rootURL = rootURL
        self.currentDirectoryURL = currentDirectoryURL ?? rootURL
    }
}

public final class FileBrowser: @unchecked Sendable {
    public static let shared = FileBrowser()

    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public init() {}

    public static let commonSearchDirectories: [URL] = {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("project"),
            home
        ]
        return candidates.filter { fm.fileExists(atPath: $0.path) }
    }()

    public func expandPath(_ path: String) -> String {
        PathResolver.expandPath(path)
    }

    public func formatAutocompletePath(for item: SearchItem, currentQuery: String) -> String {
        let trimmed = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let (basePath, _) = PathResolver.splitPathQuery(trimmed)
        let isDirectory = (item.category == .directory)
        let itemTitle = item.title

        if !basePath.isEmpty {
            if isDirectory {
                let cleanTitle = itemTitle.hasSuffix("/") ? itemTitle : (itemTitle + "/")
                return basePath.hasSuffix("/") ? (basePath + cleanTitle) : (basePath + "/" + cleanTitle)
            } else {
                return basePath.hasSuffix("/") ? (basePath + itemTitle) : (basePath + "/" + itemTitle)
            }
        } else {
            if isDirectory {
                return itemTitle.hasSuffix("/") ? itemTitle : (itemTitle + "/")
            } else {
                return itemTitle
            }
        }
    }

    public func determinePreviewType(for url: URL, isDirectory: Bool) -> PreviewType {
        if isDirectory {
            let count = (try? fileManager.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? 0
            return .directory(url, itemCount: count)
        }

        let ext = url.pathExtension.lowercased()

        // Images
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "heic", "tiff", "bmp"]
        if imageExtensions.contains(ext) {
            return .image(url)
        }

        // Videos
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi"]
        if videoExtensions.contains(ext) {
            return .video(url)
        }

        // Audio
        let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "flac", "aac", "ogg"]
        if audioExtensions.contains(ext) {
            return .audio(url)
        }

        // PDF
        if ext == "pdf" {
            return .pdf(url)
        }

        // Code
        let codeExtensions: Set<String> = [
            "swift", "py", "js", "ts", "json", "yaml", "yml", "sh", "html", "css",
            "c", "h", "cpp", "rs", "go", "toml", "env", "sql", "zsh", "bash", "xml"
        ]
        if codeExtensions.contains(ext) {
            return .code(url, language: ext)
        }

        // Text
        let textExtensions: Set<String> = ["txt", "md", "log", "rtf"]
        if textExtensions.contains(ext) {
            return .text(url)
        }

        return .fileMetadata(url)
    }

    public func browseDirectory(targetURL: URL, rootURL: URL? = nil, displayPrefix: String = "", filter: String = "") -> [SearchItem] {
        let standardizedTarget = targetURL.standardizedFileURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedTarget.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        var contentsURLs: [URL] = []
        if let urls = try? fileManager.contentsOfDirectory(
            at: standardizedTarget,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            contentsURLs = urls
        } else if let names = try? fileManager.contentsOfDirectory(atPath: standardizedTarget.path) {
            contentsURLs = names.map { standardizedTarget.appendingPathComponent($0) }
        } else {
            return []
        }

        var items: [SearchItem] = []

        for url in contentsURLs {
            let filename = url.lastPathComponent
            if filename.hasPrefix(".") { continue }

            var matchScore = 100
            var matchedIndices: [Int] = []

            if !filter.isEmpty {
                guard let match = FuzzyMatcher.match(query: filter, target: filename) else {
                    continue
                }
                matchScore = match.score
                matchedIndices = match.matchedIndices
            }

            var itemIsDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &itemIsDir)
            guard exists else { continue }

            let isDirectory = itemIsDir.boolValue
            let previewType = determinePreviewType(for: url, isDirectory: isDirectory)

            // Subtitle formatting
            var subtitleParts: [String] = []
            if isDirectory {
                subtitleParts.append("Folder")
                if case .directory(_, let count) = previewType {
                    subtitleParts.append("\(count) item\(count == 1 ? "" : "s")")
                }
            } else {
                if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                    let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    subtitleParts.append(formattedSize)
                }
                if let resources = try? url.resourceValues(forKeys: [.contentModificationDateKey]), let modDate = resources.contentModificationDate {
                    subtitleParts.append(dateFormatter.string(from: modDate))
                }
            }

            let subtitle = subtitleParts.joined(separator: " • ")
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let category: SearchCategory = isDirectory ? .directory : .file

            if isDirectory {
                if filter.isEmpty {
                    matchScore = 110
                } else {
                    matchScore += 20
                }
            }

            let itemSuffix = isDirectory ? (filename + "/") : filename
            let autocompletePayload: String
            if displayPrefix.isEmpty {
                autocompletePayload = itemSuffix
            } else {
                autocompletePayload = displayPrefix.hasSuffix("/") ? (displayPrefix + itemSuffix) : (displayPrefix + "/" + itemSuffix)
            }

            let searchItem = SearchItem(
                id: "file:\(url.path)",
                title: filename,
                subtitle: subtitle.isEmpty ? url.path : subtitle,
                category: category,
                score: matchScore,
                icon: icon,
                actionPayload: url.path,
                matchedIndices: matchedIndices,
                previewDetail: url.path,
                previewType: previewType,
                previewURL: url,
                autocompletePayload: autocompletePayload,
                action: {
                    NSWorkspace.shared.open(url)
                }
            )

            items.append(searchItem)
        }

        // Sort folders first alphabetically (or by score descending if filtered), then files alphabetically (or by score descending if filtered)
        items.sort { a, b in
            if a.category == .directory && b.category != .directory {
                return true
            }
            if a.category != .directory && b.category == .directory {
                return false
            }
            if !filter.isEmpty {
                if a.score != b.score {
                    return a.score > b.score
                }
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        if let root = rootURL, standardizedTarget.path != root.standardizedFileURL.path {
            let parentItem = SearchItem(
                id: "file:..",
                title: "..",
                subtitle: "Parent Directory • Go back",
                category: .directory,
                score: 10000,
                icon: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"),
                actionPayload: "..",
                autocompletePayload: "..",
                action: { true }
            )
            items.insert(parentItem, at: 0)
        }

        return items
    }

    public func browseDirectory(path: String) -> [SearchItem] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = PathResolver.expandPath(trimmed)
        var isDir: ObjCBool = false
        let isExistingDirectory = fileManager.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue

        let (basePath, subFilter) = PathResolver.splitPathQuery(trimmed)

        let targetDirURL: URL
        let filterPrefix: String

        if PathResolver.isDirectorySession(trimmed) || isExistingDirectory {
            targetDirURL = URL(fileURLWithPath: expanded)
            filterPrefix = ""
        } else {
            if !basePath.isEmpty {
                let expandedBase = PathResolver.expandPath(basePath)
                targetDirURL = URL(fileURLWithPath: expandedBase)
                filterPrefix = subFilter
            } else {
                let candidateURL = URL(fileURLWithPath: expanded)
                targetDirURL = candidateURL.deletingLastPathComponent()
                filterPrefix = candidateURL.lastPathComponent
            }
        }

        guard fileManager.fileExists(atPath: targetDirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: targetDirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [SearchItem] = []

        for url in contents {
            let filename = url.lastPathComponent
            if filename.hasPrefix(".") { continue }

            var matchScore = 100
            var matchedIndices: [Int] = []

            if !filterPrefix.isEmpty {
                guard let match = FuzzyMatcher.match(query: filterPrefix, target: filename) else {
                    continue
                }
                matchScore = match.score
                matchedIndices = match.matchedIndices
            }

            var itemIsDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &itemIsDir)
            guard exists else { continue }

            let isDirectory = itemIsDir.boolValue
            let previewType = determinePreviewType(for: url, isDirectory: isDirectory)

            // Subtitle formatting
            var subtitleParts: [String] = []
            if isDirectory {
                subtitleParts.append("Folder")
                if case .directory(_, let count) = previewType {
                    subtitleParts.append("\(count) item\(count == 1 ? "" : "s")")
                }
            } else {
                if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                    let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    subtitleParts.append(formattedSize)
                }
                if let resources = try? url.resourceValues(forKeys: [.contentModificationDateKey]), let modDate = resources.contentModificationDate {
                    subtitleParts.append(dateFormatter.string(from: modDate))
                }
            }

            let subtitle = subtitleParts.joined(separator: " • ")
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let category: SearchCategory = isDirectory ? .directory : .file

            if isDirectory {
                if filterPrefix.isEmpty {
                    matchScore = 110
                } else {
                    matchScore += 20
                }
            }

            let autocompletePayload: String
            if isDirectory {
                autocompletePayload = basePath.isEmpty ? (filename + "/") : (basePath.hasSuffix("/") ? (basePath + filename + "/") : (basePath + "/" + filename + "/"))
            } else {
                autocompletePayload = basePath.isEmpty ? filename : (basePath.hasSuffix("/") ? (basePath + filename) : (basePath + "/" + filename))
            }

            let searchItem = SearchItem(
                id: "file:\(url.path)",
                title: filename,
                subtitle: subtitle.isEmpty ? url.path : subtitle,
                category: category,
                score: matchScore,
                icon: icon,
                actionPayload: url.path,
                matchedIndices: matchedIndices,
                previewDetail: url.path,
                previewType: previewType,
                previewURL: url,
                autocompletePayload: autocompletePayload,
                action: {
                    NSWorkspace.shared.open(url)
                }
            )

            items.append(searchItem)
        }

        // Sort folders first alphabetically (or by score descending if filtered), then files alphabetically (or by score descending if filtered)
        items.sort { a, b in
            if a.category == .directory && b.category != .directory {
                return true
            }
            if a.category != .directory && b.category == .directory {
                return false
            }
            if !filterPrefix.isEmpty {
                if a.score != b.score {
                    return a.score > b.score
                }
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        if PathResolver.isDirectorySession(trimmed) && PathResolver.canGoBack(path: trimmed) {
            if let parent = PathResolver.parentPath(of: trimmed) {
                let parentItem = SearchItem(
                    id: "file:..",
                    title: "..",
                    subtitle: "Parent Directory • Go back",
                    category: .directory,
                    score: 10000,
                    icon: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"),
                    actionPayload: parent,
                    autocompletePayload: parent,
                    action: { true }
                )
                items.insert(parentItem, at: 0)
            }
        }

        return items
    }

    public func searchFiles(query: String, directories: [URL]? = nil) -> [SearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let searchDirs = directories ?? FileBrowser.commonSearchDirectories
        var results: [SearchItem] = []
        var seenPaths = Set<String>()

        for dir in searchDirs {
            scanAndMatch(
                directory: dir,
                query: trimmed,
                currentDepth: 1,
                maxDepth: 3,
                results: &results,
                seenPaths: &seenPaths
            )
            if results.count >= 50 { break }
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(40))
    }

    private func scanAndMatch(
        directory: URL,
        query: String,
        currentDepth: Int,
        maxDepth: Int,
        results: inout [SearchItem],
        seenPaths: inout Set<String>
    ) {
        guard currentDepth <= maxDepth else { return }

        let ignoredFolders: Set<String> = [
            ".git", ".build", "node_modules", "DerivedData", ".Trash", "Library", "Caches"
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let filename = url.lastPathComponent
            let path = url.path

            if ignoredFolders.contains(filename) { continue }
            if seenPaths.contains(path) { continue }
            seenPaths.insert(path)

            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDir)
            guard exists else { continue }

            let isDirectory = isDir.boolValue

            if let match = FuzzyMatcher.match(query: query, target: filename) {
                let previewType = determinePreviewType(for: url, isDirectory: isDirectory)
                var subtitleParts: [String] = []

                if isDirectory {
                    subtitleParts.append("Folder")
                    if case .directory(_, let count) = previewType {
                        subtitleParts.append("\(count) items")
                    }
                } else {
                    if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                        subtitleParts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }

                subtitleParts.append(path)
                let subtitle = subtitleParts.joined(separator: " • ")
                let icon = NSWorkspace.shared.icon(forFile: path)
                let category: SearchCategory = isDirectory ? .directory : .file

                let autocompletePayload = isDirectory ? (filename.hasSuffix("/") ? filename : (filename + "/")) : filename

                let item = SearchItem(
                    id: "file:\(path)",
                    title: filename,
                    subtitle: subtitle,
                    category: category,
                    score: match.score + (isDirectory ? 10 : 0),
                    icon: icon,
                    actionPayload: path,
                    matchedIndices: match.matchedIndices,
                    previewDetail: path,
                    previewType: previewType,
                    previewURL: url,
                    autocompletePayload: autocompletePayload,
                    action: {
                        NSWorkspace.shared.open(url)
                    }
                )
                results.append(item)
            }

            if isDirectory && !path.hasSuffix(".app") {
                scanAndMatch(
                    directory: url,
                    query: query,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    results: &results,
                    seenPaths: &seenPaths
                )
            }
        }
    }
}
