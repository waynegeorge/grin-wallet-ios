// This file is part of Grin Wallet iOS.
//
// Copyright (C) 2026 Grin Works
//
// Grin Wallet iOS is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Grin Wallet iOS is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Grin Wallet iOS. If not, see <https://www.gnu.org/licenses/>.

//
//  PasswordStrength.swift
//  grin-ios
//
//  zxcvbn-inspired password strength evaluator.
//

import SwiftUI

struct PasswordStrength {
    let score: Int       // 0-4
    let label: String
    let colour: Color
    let fraction: CGFloat

    /// Common passwords / patterns to penalise
    private static let commonPasswords: Set<String> = [
        "password", "12345678", "123456789", "1234567890", "qwerty12",
        "iloveyou", "sunshine", "princess", "football", "charlie",
        "trustno1", "dragon12", "baseball", "letmein1", "monkey12",
        "master12", "michael1", "shadow12", "jennifer", "abcdefgh",
        "password1", "qwerty123", "abc12345", "password123"
    ]

    private static let keyboardPatterns = [
        "qwertyui", "asdfghjk", "zxcvbnm", "12345678", "87654321",
        "qweasdzx", "1q2w3e4r", "1qaz2wsx"
    ]

    /// Evaluate password strength (zxcvbn-style scoring)
    static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else {
            return PasswordStrength(score: 0, label: "", colour: .gray, fraction: 0)
        }

        var score: Double = 0
        let lower = password.lowercased()

        // --- Length contribution ---
        // Base entropy from length
        score += Double(min(password.count, 30)) * 0.5

        // Bonus for longer passwords
        if password.count >= 12 { score += 1.0 }
        if password.count >= 16 { score += 1.0 }
        if password.count >= 20 { score += 0.5 }

        // --- Character class diversity ---
        let hasLower = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasUpper = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSymbol = password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil

        let classCount = [hasLower, hasUpper, hasDigit, hasSymbol].filter { $0 }.count
        score += Double(classCount) * 1.5

        // --- Penalties ---

        // Common password check
        if commonPasswords.contains(lower) {
            score = max(score - 8, 0)
        }

        // Keyboard pattern check
        for pattern in keyboardPatterns {
            if lower.contains(pattern) {
                score = max(score - 3, 0)
            }
        }

        // Repeated characters (e.g. "aaaaaa")
        let uniqueChars = Set(password).count
        let repeatRatio = Double(uniqueChars) / Double(password.count)
        if repeatRatio < 0.4 {
            score = max(score - 3, 0)
        } else if repeatRatio < 0.6 {
            score = max(score - 1.5, 0)
        }

        // Sequential characters (abc, 123, etc.)
        var sequentialCount = 0
        let chars = Array(lower.unicodeScalars)
        guard chars.count >= 3 else {
            return from(score: password.count >= 8 ? 1 : 0)
        }
        for i in 0..<(chars.count - 2) {
            let a = chars[i].value
            let b = chars[i + 1].value
            let c = chars[i + 2].value
            if b == a + 1 && c == b + 1 { sequentialCount += 1 }
            if b == a - 1 && c == b - 1 { sequentialCount += 1 }
        }
        if sequentialCount > 2 {
            score = max(score - Double(sequentialCount), 0)
        }

        // All same case penalty
        if hasLower && !hasUpper && !hasDigit && !hasSymbol {
            score = max(score - 1, 0)
        }

        // --- Map to 0-4 score ---
        let finalScore: Int
        if password.count < 8 {
            finalScore = 0  // Always weak if under minimum
        } else if score < 5 {
            finalScore = 0
        } else if score < 8 {
            finalScore = 1
        } else if score < 11 {
            finalScore = 2
        } else if score < 14 {
            finalScore = 3
        } else {
            finalScore = 4
        }

        return from(score: finalScore)
    }

    private static func from(score: Int) -> PasswordStrength {
        switch score {
        case 0:
            return PasswordStrength(score: 0, label: "Weak", colour: .red, fraction: 0.15)
        case 1:
            return PasswordStrength(score: 1, label: "Fair", colour: .orange, fraction: 0.35)
        case 2:
            return PasswordStrength(score: 2, label: "Good", colour: .yellow, fraction: 0.55)
        case 3:
            return PasswordStrength(score: 3, label: "Strong", colour: .green, fraction: 0.8)
        default:
            return PasswordStrength(score: 4, label: "Very Strong", colour: .green, fraction: 1.0)
        }
    }
}
