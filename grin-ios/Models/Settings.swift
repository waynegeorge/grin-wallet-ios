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
//  Settings.swift
//  grin-ios
//

import SwiftUI

enum Currency: String, CaseIterable {
    case usd = "USD"
    case gbp = "GBP"
    case eur = "EUR"

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .gbp: return "£"
        case .eur: return "€"
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum DateFormatStyle: String, CaseIterable {
    case dmy = "DD/MM/YYYY"
    case mdy = "MM/DD/YYYY"
}

@Observable
class AppSettings {
    var currency: Currency = .gbp
    var appearanceMode: AppearanceMode = .dark
    var dateFormat: DateFormatStyle = .dmy
    var grinDecimalPlaces: Int = UserDefaults.standard.object(forKey: "grinDecimalPlaces") as? Int ?? 2 {
        didSet { UserDefaults.standard.set(grinDecimalPlaces, forKey: "grinDecimalPlaces") }
    }
    var advancedMode: Bool = false
    var showQuickButtons: Bool = false
    var quickButton1: Double = -5
    var quickButton2: Double = -1
    var quickButton3: Double = 1
    var quickButton4: Double = 5

    // Cached balance (shown on launch before wallet loads)
    var lastKnownBalance: Double {
        get { UserDefaults.standard.double(forKey: "lastKnownBalance") }
        set { UserDefaults.standard.set(newValue, forKey: "lastKnownBalance") }
    }

    // Cached transactions (shown on launch before wallet loads)
    var lastKnownTransactions: [Transaction] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "lastKnownTransactions"),
                  let txs = try? JSONDecoder().decode([Transaction].self, from: data) else { return [] }
            return txs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "lastKnownTransactions")
            }
        }
    }

    // Last scan result (observable + persisted to UserDefaults)
    var lastScanDate: Date? = UserDefaults.standard.object(forKey: "lastScanDate") as? Date {
        didSet { UserDefaults.standard.set(lastScanDate, forKey: "lastScanDate") }
    }

    var lastScanResult: String? = UserDefaults.standard.string(forKey: "lastScanResult") {
        didSet { UserDefaults.standard.set(lastScanResult, forKey: "lastScanResult") }
    }

    var lastScanDuration: TimeInterval = UserDefaults.standard.double(forKey: "lastScanDuration") {
        didSet { UserDefaults.standard.set(lastScanDuration, forKey: "lastScanDuration") }
    }

    // Seed phrase word count for new wallets (default 12)
    var seedWordCount: Int = {
        let val = UserDefaults.standard.integer(forKey: "seedWordCount")
        return val > 0 ? val : 12
    }() {
        didSet { UserDefaults.standard.set(seedWordCount, forKey: "seedWordCount") }
    }

    static let validWordCounts = [12, 15, 18, 21, 24]

    // Minimum confirmations before outputs are spendable (default 10)
    var minimumConfirmations: Int = {
        let val = UserDefaults.standard.integer(forKey: "minimumConfirmations")
        return val > 0 ? val : 10
    }() {
        didSet { UserDefaults.standard.set(minimumConfirmations, forKey: "minimumConfirmations") }
    }

    // Whether nearby peer-to-peer communications are enabled
    var nearbyEnabled: Bool = UserDefaults.standard.object(forKey: "nearbyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(nearbyEnabled, forKey: "nearbyEnabled") }
    }

    // Discovery name (used for nearby peer visibility)
    var walletDisplayName: String {
        get { UserDefaults.standard.string(forKey: "walletDisplayName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "walletDisplayName") }
    }

    /// Generate a random two-word name like "swift-falcon" for skip/default
    static func generateRandomName() -> String {
        let adjectives = [
            "swift", "bright", "calm", "bold", "keen",
            "wild", "cool", "warm", "dark", "fair",
            "glad", "iron", "jade", "mint", "noon",
            "pale", "rare", "sage", "true", "wise"
        ]
        let nouns = [
            "falcon", "cedar", "river", "ember", "storm",
            "ridge", "stone", "frost", "bloom", "drift",
            "grove", "flint", "spark", "brook", "crane",
            "maple", "pearl", "raven", "coral", "aspen"
        ]
        let adj = adjectives.randomElement()!
        let noun = nouns.randomElement()!
        return "\(adj)-\(noun)"
    }

    // Block height calibration samples: [[height, unixTimestamp], ...]
    // Populated on first launch by querying the node for headers at regular intervals.
    var heightCalibration: [[Double]] {
        get {
            (UserDefaults.standard.array(forKey: "heightCalibration") as? [[Double]]) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "heightCalibration")
        }
    }

    /// Safety margin subtracted from estimated block heights (1 day of blocks).
    /// Ensures scans don't overshoot and miss outputs near the target date.
    private static let heightSafetyMargin: UInt64 = 1440

    /// Estimate block height for a given date using calibration samples.
    /// Falls back to simple 60s/block calculation from current tip if no samples.
    /// Subtracts a safety margin to avoid missing outputs near the boundary.
    func estimateHeight(for date: Date, currentHeight: UInt64) -> UInt64 {
        let raw = estimateHeightRaw(for: date, currentHeight: currentHeight)
        // Subtract safety margin to avoid missing outputs near the target date
        if raw <= Self.heightSafetyMargin { return 1 }
        return raw - Self.heightSafetyMargin
    }

    private func estimateHeightRaw(for date: Date, currentHeight: UInt64) -> UInt64 {
        let target = date.timeIntervalSince1970
        let samples = heightCalibration

        // Need at least 2 samples for interpolation
        guard samples.count >= 2 else {
            // Fallback: 60s per block from now
            let secondsAgo = Date().timeIntervalSince(date)
            let blocksAgo = UInt64(max(0, secondsAgo / 60))
            if blocksAgo >= currentHeight { return 1 }
            return currentHeight - blocksAgo
        }

        // If target is before earliest sample, extrapolate from first two
        if target <= samples.first![1] {
            let s0 = samples[0]
            let s1 = samples[1]
            let rate = (s1[0] - s0[0]) / (s1[1] - s0[1]) // blocks per second
            let h = s0[0] + rate * (target - s0[1])
            return UInt64(max(1, h))
        }

        // If target is after last sample, extrapolate from last two
        if target >= samples.last![1] {
            let s0 = samples[samples.count - 2]
            let s1 = samples[samples.count - 1]
            let rate = (s1[0] - s0[0]) / (s1[1] - s0[1])
            let h = s1[0] + rate * (target - s1[1])
            return min(UInt64(max(1, h)), currentHeight)
        }

        // Interpolate between bracketing samples
        for i in 0..<(samples.count - 1) {
            let s0 = samples[i]
            let s1 = samples[i + 1]
            if target >= s0[1] && target <= s1[1] {
                let fraction = (target - s0[1]) / (s1[1] - s0[1])
                let h = s0[0] + fraction * (s1[0] - s0[0])
                return UInt64(max(1, h))
            }
        }

        return 1
    }

    // Node configuration
    var nodeURL: String = "testnet.grinffindor.org"
    var nodePort: String = "443"
    var nodeAPISecret: String = ""
    var nodeUseTLS: Bool = true

    var nodeScheme: String {
        nodeUseTLS ? "https" : "http"
    }

    /// Base URL for FFI (Rust client appends /v2/foreign itself)
    var nodeBaseURL: String {
        let portSuffix = (nodeUseTLS && nodePort == "443") || (!nodeUseTLS && nodePort == "80") ? "" : ":\(nodePort)"
        return "\(nodeScheme)://\(nodeURL)\(portSuffix)"
    }

    var fullNodeURL: String {
        "\(nodeBaseURL)/v2/owner"
    }

    var foreignNodeURL: String {
        "\(nodeBaseURL)/v2/foreign"
    }
}
