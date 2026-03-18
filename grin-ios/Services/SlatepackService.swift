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
//  SlatepackService.swift
//  grin-ios
//

import Foundation

actor SlatepackService {
    static let shared = SlatepackService()

    private init() {}

    // MARK: - Armor / Dearmor

    func armor(slate: Data) async -> Slatepack {
        // Mock: base64 encode the data as payload
        let payload = slate.base64EncodedString()
        let raw = "BEGINSLATEPACK. \(payload) . ENDSLATEPACK."
        return Slatepack(
            header: "BEGINSLATEPACK.",
            payload: payload,
            footer: ". ENDSLATEPACK.",
            rawString: raw
        )
    }

    func dearmor(slatepack: String) async throws -> Data {
        let trimmed = slatepack
            .replacingOccurrences(of: "BEGINSLATEPACK.", with: "")
            .replacingOccurrences(of: ". ENDSLATEPACK.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = Data(base64Encoded: trimmed) else {
            throw SlatepackError.invalidFormat
        }

        return data
    }

    // MARK: - Validation

    func isValidSlatepack(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("BEGINSLATEPACK.") && trimmed.hasSuffix(". ENDSLATEPACK.")
    }

    // MARK: - Parse

    func parse(_ string: String) -> Slatepack? {
        parseSync(string)
    }

    /// Synchronous parse — safe to call from non-async contexts.
    nonisolated func parseSync(_ string: String) -> Slatepack? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("BEGINSLATEPACK.") && trimmed.hasSuffix(". ENDSLATEPACK.") else { return nil }

        let payload = trimmed
            .replacingOccurrences(of: "BEGINSLATEPACK.", with: "")
            .replacingOccurrences(of: ". ENDSLATEPACK.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Slatepack(
            header: "BEGINSLATEPACK.",
            payload: payload,
            footer: ". ENDSLATEPACK.",
            rawString: trimmed
        )
    }

    // MARK: - Mock Generation

    func generateMockSlatepack() -> Slatepack {
        Slatepack.mock(length: 300)
    }
}

enum SlatepackError: Error, LocalizedError {
    case invalidFormat
    case decodingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid slatepack format"
        case .decodingFailed: return "Failed to decode slatepack"
        case .encodingFailed: return "Failed to encode slatepack"
        }
    }
}
