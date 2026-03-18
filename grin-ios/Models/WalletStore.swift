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
//  WalletStore.swift
//  grin-ios
//
//  Manages multiple wallets on device.
//

import Foundation

@Observable
class WalletStore {
    static let shared = WalletStore()

    /// List of wallet names
    var wallets: [String] = UserDefaults.standard.stringArray(forKey: "grin_wallets") ?? [] {
        didSet { UserDefaults.standard.set(wallets, forKey: "grin_wallets") }
    }

    /// Currently active wallet name
    var activeWallet: String? = UserDefaults.standard.string(forKey: "grin_active_wallet") {
        didSet { UserDefaults.standard.set(activeWallet, forKey: "grin_active_wallet") }
    }

    /// Whether onboarding is complete (at least one wallet exists)
    var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "grin_onboarded") {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: "grin_onboarded") }
    }

    /// Whether Face ID / biometric unlock is enabled
    var biometricEnabled: Bool = UserDefaults.standard.bool(forKey: "grin_biometric_enabled") {
        didSet { UserDefaults.standard.set(biometricEnabled, forKey: "grin_biometric_enabled") }
    }

    /// Check if a wallet exists on disk (survives app reinstall)
    func walletExistsOnDisk(name: String = "default") -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tomlPath = docs.appendingPathComponent("grin_wallets/\(name)/grin-wallet.toml")
        return FileManager.default.fileExists(atPath: tomlPath.path)
    }

    /// Detect any wallet on disk and recover state if UserDefaults was wiped
    func recoverIfNeeded() {
        if !isOnboarded && walletExistsOnDisk() {
            // Wallet files exist but UserDefaults were wiped (reinstall)
            if !wallets.contains("default") {
                var list = wallets
                list.append("default")
                wallets = list
            }
            if activeWallet == nil {
                activeWallet = "default"
            }
            isOnboarded = true
        }
    }

    func addWallet(name: String, password: String) {
        var list = wallets
        if !list.contains(name) {
            list.append(name)
            wallets = list
        }
        // Store password in Keychain (basic implementation)
        savePassword(password, for: name)
    }

    func removeWallet(name: String) {
        var list = wallets
        list.removeAll { $0 == name }
        wallets = list
        deletePassword(for: name)
        if activeWallet == name {
            activeWallet = list.first
        }
    }

    func password(for walletName: String) -> String? {
        loadPassword(for: walletName)
    }

    // MARK: - Keychain

    private func savePassword(_ password: String, for wallet: String) {
        let key = "grin_wallet_\(wallet)"
        let data = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadPassword(for wallet: String) -> String? {
        let key = "grin_wallet_\(wallet)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deletePassword(for wallet: String) {
        let key = "grin_wallet_\(wallet)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
