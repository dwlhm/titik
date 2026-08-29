import Foundation

public struct FuzzyMatchResult: Equatable, Sendable {
    public let score: Int
    public let matchedIndices: [Int]

    public init(score: Int, matchedIndices: [Int]) {
        self.score = score
        self.matchedIndices = matchedIndices
    }
}

public enum FuzzyMatcher {
    public static func match(query: String, target: String) -> FuzzyMatchResult? {
        let qChars = Array(query.lowercased())
        let tChars = Array(target.lowercased())
        let origChars = Array(target)

        guard !qChars.isEmpty else {
            return FuzzyMatchResult(score: 0, matchedIndices: [])
        }
        guard qChars.count <= tChars.count else {
            return nil
        }

        var matchedIndices: [Int] = []
        var qIdx = 0
        var score = 0
        var prevMatchIdx = -1
        var consecutiveCount = 0

        for (tIdx, tChar) in tChars.enumerated() {
            guard qIdx < qChars.count else { break }

            if tChar == qChars[qIdx] {
                matchedIndices.append(tIdx)

                var charScore = 10 // base character match score

                // 1. Prefix match bonus
                if tIdx == 0 {
                    charScore += 100
                }

                // 2. Word boundary bonus (following space, hyphen, underscore, slash, dot)
                if tIdx > 0 {
                    let prevChar = tChars[tIdx - 1]
                    if prevChar == " " || prevChar == "-" || prevChar == "_" || prevChar == "/" || prevChar == "." {
                        charScore += 30
                    }
                    // CamelCase boundary: previous was lowercase and current in original target is uppercase
                    if origChars[tIdx - 1].isLowercase && origChars[tIdx].isUppercase {
                        charScore += 25
                    }
                }

                // 3. Consecutive match bonus
                if prevMatchIdx != -1 && tIdx == prevMatchIdx + 1 {
                    consecutiveCount += 1
                    charScore += (consecutiveCount * 20)
                } else {
                    consecutiveCount = 0
                    if prevMatchIdx != -1 {
                        // Gap penalty
                        let gap = tIdx - prevMatchIdx - 1
                        charScore -= (gap * 1)
                    }
                }

                score += charScore
                prevMatchIdx = tIdx
                qIdx += 1
            }
        }

        // Must have matched every query character
        guard qIdx == qChars.count else {
            return nil
        }

        // Exact substring bonus
        if let range = target.range(of: query, options: .caseInsensitive) {
            let startIdx = target.distance(from: target.startIndex, to: range.lowerBound)
            if startIdx == 0 {
                score += 50
            } else {
                score += 25
            }
        }

        // Full exact match bonus
        if query.caseInsensitiveCompare(target) == .orderedSame {
            score += 150
        }

        return FuzzyMatchResult(score: score, matchedIndices: matchedIndices)
    }
}
