//
//  TextDiffAlgorithm.swift
//  Hex
//
//  Advanced text diffing algorithm for detecting corrections
//  Uses Myers diff algorithm to accurately track word-level changes
//

import Foundation
import HexCore

/// Represents a diff operation in the Myers algorithm
enum DiffOperation: Equatable {
    case delete(index: Int, word: String)
    case insert(index: Int, word: String)
    case equal(index: Int, word: String)
}

/// Advanced text diff engine using Myers algorithm
struct TextDiffAlgorithm {

    /// Tokenize text into words, handling both English and Chinese
    /// - For English: split by whitespace
    /// - For Chinese: split by character for better granularity
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""

        for char in text {
            let isChinese = ("\u{4E00}"..."\u{9FFF}").contains(char)
            let isWhitespace = char.isWhitespace
            let isPunctuation = char.isPunctuation

            if isChinese {
                // Flush current English word if any
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                // Add Chinese character as individual token
                tokens.append(String(char))
            } else if isWhitespace {
                // Flush current word
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else if isPunctuation {
                // Flush current word
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                // Add punctuation as separate token
                tokens.append(String(char))
            } else {
                // Regular character (English letter, number, etc.)
                currentToken.append(char)
            }
        }

        // Flush remaining token
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }

    /// Perform Myers diff algorithm to find minimal edit script
    /// Returns list of diff operations
    static func diff(_ original: [String], _ edited: [String]) -> [DiffOperation] {
        let n = original.count
        let m = edited.count
        let max = n + m

        // V array for Myers algorithm
        var v = [Int: Int]()
        v[1] = 0

        // Trace for backtracking
        var trace: [[Int: Int]] = []

        // Forward search
        for d in 0...max {
            trace.append(v)

            for k in stride(from: -d, through: d, by: 2) {
                var x: Int

                if k == -d || (k != d && v[k - 1]! < v[k + 1]!) {
                    x = v[k + 1]!
                } else {
                    x = v[k - 1]! + 1
                }

                var y = x - k

                // Follow diagonal as far as possible
                while x < n && y < m && original[x] == edited[y] {
                    x += 1
                    y += 1
                }

                v[k] = x

                // Check if we've reached the end
                if x >= n && y >= m {
                    return backtrack(trace, original, edited)
                }
            }
        }

        // Should never reach here if inputs are valid
        return []
    }

    /// Backtrack through the trace to build the diff operations
    private static func backtrack(_ trace: [[Int: Int]], _ original: [String], _ edited: [String]) -> [DiffOperation] {
        var x = original.count
        var y = edited.count
        var operations: [DiffOperation] = []

        for d in (0..<trace.count).reversed() {
            let v = trace[d]
            let k = x - y

            var prevK: Int
            if k == -d || (k != d && v[k - 1]! < v[k + 1]!) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }

            let prevX = v[prevK]!
            let prevY = prevX - prevK

            // Follow diagonal backwards
            while x > prevX && y > prevY {
                x -= 1
                y -= 1
                operations.insert(.equal(index: x, word: original[x]), at: 0)
            }

            if d > 0 {
                if x == prevX {
                    // Insert
                    y -= 1
                    operations.insert(.insert(index: y, word: edited[y]), at: 0)
                } else {
                    // Delete
                    x -= 1
                    operations.insert(.delete(index: x, word: original[x]), at: 0)
                }
            }
        }

        return operations
    }

    /// Extract corrections from diff operations
    /// Groups consecutive delete+insert as replacements
    static func extractCorrections(from operations: [DiffOperation]) -> [TextCorrection] {
        var corrections: [TextCorrection] = []
        var i = 0

        while i < operations.count {
            switch operations[i] {
            case .delete(_, let deletedWord):
                // Look ahead for matching insert
                if i + 1 < operations.count, case .insert(_, let insertedWord) = operations[i + 1] {
                    // This is a replacement
                    let original = deletedWord.trimmingCharacters(in: .punctuationCharacters)
                    let corrected = insertedWord.trimmingCharacters(in: .punctuationCharacters)

                    // Only add if they're actually different and non-empty
                    if !original.isEmpty && !corrected.isEmpty && original.lowercased() != corrected.lowercased() {
                        corrections.append(TextCorrection(
                            original: original,
                            corrected: corrected
                        ))
                    }
                    i += 2 // Skip both delete and insert
                } else {
                    i += 1
                }

            case .insert:
                // Standalone insert (not paired with delete) - skip
                i += 1

            case .equal:
                i += 1
            }
        }

        return corrections
    }

    /// Main entry point: detect corrections between original and edited text
    static func detectCorrections(original: String, edited: String) -> [TextCorrection] {
        guard original != edited else { return [] }

        let originalTokens = tokenize(original)
        let editedTokens = tokenize(edited)

        let operations = diff(originalTokens, editedTokens)
        return extractCorrections(from: operations)
    }
}

// MARK: - Smart Hotword Extraction

extension TextDiffAlgorithm {

    /// Extract meaningful hotwords from corrections
    /// - Filters out common words
    /// - Handles both English and Chinese
    static func extractHotwords(
        from corrections: [TextCorrection],
        commonWords: Set<String>
    ) -> [String] {
        var hotwords: [String] = []

        for correction in corrections {
            let correctedText = correction.corrected.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Check if the corrected text contains Chinese characters
            let containsChinese = correctedText.rangeOfCharacter(
                from: CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
            ) != nil

            if containsChinese {
                // For Chinese corrections:
                // Add the entire corrected phrase if it's 2-10 characters and not common
                let length = correctedText.count
                if length >= 2 && length <= 10 && !commonWords.contains(correctedText) {
                    hotwords.append(correctedText)
                }
            } else {
                // For English corrections:
                // Split by whitespace and extract individual words
                let words = correctedText.split(separator: " ").map {
                    String($0).trimmingCharacters(in: .punctuationCharacters)
                }

                for word in words {
                    // Skip short words (< 3 chars) and common words
                    guard word.count >= 3, !commonWords.contains(word.lowercased()) else { continue }
                    hotwords.append(word)
                }
            }
        }

        return hotwords
    }
}
