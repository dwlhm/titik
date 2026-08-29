import Foundation

public enum PathResolver: Sendable {
    public static func expandPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let pwd = fm.currentDirectoryPath

        if trimmed.isEmpty || trimmed == "~" {
            return home
        }
        if trimmed == "~/" {
            return home + "/"
        }
        if trimmed.hasPrefix("~/") {
            let remainder = String(trimmed.dropFirst(2))
            return (home as NSString).appendingPathComponent(remainder)
        }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        if trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return URL(fileURLWithPath: (pwd as NSString).appendingPathComponent(trimmed)).standardized.path
        }

        // Relative path without explicit prefix
        let pwdCandidate = (pwd as NSString).appendingPathComponent(trimmed)
        if fm.fileExists(atPath: pwdCandidate) {
            return pwdCandidate
        }

        let homeCandidate = (home as NSString).appendingPathComponent(trimmed)
        if fm.fileExists(atPath: homeCandidate) {
            return homeCandidate
        }

        for searchDir in FileBrowser.commonSearchDirectories {
            let candidate = searchDir.appendingPathComponent(trimmed).path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return pwdCandidate
    }

    public static func contractPath(_ path: String, originalQuery: String) -> String {
        let trimmedQuery = originalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let pwd = fm.currentDirectoryPath

        if trimmedQuery.hasPrefix("~") {
            if path == home {
                return "~"
            } else if path.hasPrefix(home + "/") {
                return "~" + String(path.dropFirst(home.count))
            }
            return path
        }

        if trimmedQuery.hasPrefix("/") {
            return path
        }

        // Relative query representation preservation
        if trimmedQuery.hasPrefix("./") {
            if path == pwd {
                return "./"
            } else if path.hasPrefix(pwd + "/") {
                return "./" + String(path.dropFirst(pwd.count + 1))
            }
        }

        if path.hasPrefix(pwd + "/") {
            return String(path.dropFirst(pwd.count + 1))
        } else if path == pwd {
            return "."
        }

        if path.hasPrefix(home + "/") {
            let relativeToHome = String(path.dropFirst(home.count + 1))
            if trimmedQuery.hasPrefix(relativeToHome) || relativeToHome.hasPrefix(trimmedQuery) {
                return relativeToHome
            }
        }

        for dir in FileBrowser.commonSearchDirectories {
            if path.hasPrefix(dir.path + "/") {
                let relativeToDir = String(path.dropFirst(dir.path.count + 1))
                let dirName = dir.lastPathComponent
                let candidate = dirName + "/" + relativeToDir
                if trimmedQuery.hasPrefix(dirName) || trimmedQuery.hasPrefix(candidate) {
                    return candidate
                } else if trimmedQuery.hasPrefix(relativeToDir) {
                    return relativeToDir
                }
            }
        }

        return path
    }

    public static func isPathQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("~") ||
               trimmed.hasPrefix("/") ||
               trimmed.hasPrefix("./") ||
               trimmed.hasPrefix("../") ||
               trimmed.contains("/")
    }

    public static func isDirectorySession(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "~" || trimmed == "/" || trimmed.hasSuffix("/")
    }

    public static func splitPathQuery(_ query: String) -> (basePath: String, subFilter: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDirectorySession(trimmed) {
            return (basePath: trimmed, subFilter: "")
        } else if let lastSlashIndex = trimmed.lastIndex(of: "/") {
            let nextIndex = trimmed.index(after: lastSlashIndex)
            let basePath = String(trimmed[...lastSlashIndex])
            let subFilter = String(trimmed[nextIndex...])
            return (basePath: basePath, subFilter: subFilter)
        } else {
            return (basePath: "", subFilter: trimmed)
        }
    }

    public static func canGoBack(path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "~" || trimmed == "/" || trimmed == "./" || trimmed == "../" {
            return false
        }
        if trimmed.hasPrefix("~/") {
            let withoutTilde = String(trimmed.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = withoutTilde.split(separator: "/", omittingEmptySubsequences: true)
            return parts.count >= 2
        } else if trimmed.hasPrefix("/") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            return parts.count >= 2
        } else {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            return parts.count >= 2
        }
    }

    public static func parentPath(of path: String) -> String? {
        guard canGoBack(path: path) else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~/") {
            let withoutTilde = String(trimmed.dropFirst(2))
            let parts = withoutTilde.split(separator: "/", omittingEmptySubsequences: true)
            let parentParts = parts.dropLast()
            return "~/" + parentParts.joined(separator: "/") + "/"
        } else if trimmed.hasPrefix("/") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            let parentParts = parts.dropLast()
            return "/" + parentParts.joined(separator: "/") + "/"
        } else {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            let parentParts = parts.dropLast()
            return parentParts.joined(separator: "/") + "/"
        }
    }
}
