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
//  GrinWalletBridge.swift
//  grin-ios
//
//  Swift bridge to the Rust grin-wallet FFI library.
//

import Foundation
import GrinWalletFFI

/// Swift-friendly wrapper around the Grin Wallet Rust FFI.
class GrinWalletBridge {

    /// Wallet data directory
    let dataDir: String

    /// Node API URL
    let nodeURL: String

    /// Wallet password
    private var password: String

    /// Network type
    let network: String

    init(walletName: String, nodeURL: String, password: String, network: String = "testnet") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dataDir = docs.appendingPathComponent("grin_wallets/\(walletName)").path
        self.nodeURL = nodeURL
        self.password = password
        self.network = network

        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
    }

    // MARK: - FFI Call Helper

    private func callFFI(_ ptr: UnsafeMutablePointer<CChar>?) -> [String: Any] {
        guard let ptr = ptr else {
            return ["error": "FFI returned null"]
        }
        let str = String(cString: ptr)
        grin_str_free(ptr)

        guard let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["error": "Failed to parse FFI response: \(str)"]
        }
        return json
    }

    static func isError(_ result: [String: Any]) -> Bool {
        result["error"] != nil
    }

    static func errorMessage(_ result: [String: Any]) -> String? {
        result["error"] as? String
    }

    // MARK: - Public API

    func version() -> [String: Any] {
        return callFFI(grin_wallet_version())
    }

    func walletExists() -> Bool {
        let result = callFFI(grin_wallet_exists(dataDir))
        return result["exists"] as? Bool ?? false
    }

    func createWallet(wordCount: UInt16 = 24) -> [String: Any] {
        return callFFI(grin_wallet_create(dataDir, password, network, wordCount))
    }

    func openWallet() -> [String: Any] {
        return callFFI(grin_wallet_open(dataDir, password, nodeURL))
    }

    func getBalance(minimumConfirmations: UInt64 = 10) -> [String: Any] {
        return callFFI(grin_wallet_balance(dataDir, password, nodeURL, minimumConfirmations))
    }

    func getTransactions() -> [String: Any] {
        return callFFI(grin_wallet_txs(dataDir, password, nodeURL))
    }

    func estimateFee(amount: Double) -> [String: Any] {
        let nanogrin = UInt64((amount * 1_000_000_000).rounded())
        // TODO: uncomment after rebuilding xcframework with grin_wallet_estimate_fee
        return ["status": "ok", "amount": nanogrin, "fee": UInt64(23_000_000)]
    }

    func initSend(amount: Double, minimumConfirmations: UInt64 = 10) -> [String: Any] {
        let nanogrin = UInt64((amount * 1_000_000_000).rounded())
        return callFFI(grin_wallet_send(dataDir, password, nodeURL, nanogrin, minimumConfirmations))
    }

    func receive(slatepack: String) -> [String: Any] {
        return callFFI(grin_wallet_receive(dataDir, password, nodeURL, slatepack))
    }

    func finalize(responseSlatepack: String) -> [String: Any] {
        return callFFI(grin_wallet_finalize(dataDir, password, nodeURL, responseSlatepack))
    }

    func cancel(txId: UInt32) -> [String: Any] {
        return callFFI(grin_wallet_cancel(dataDir, password, nodeURL, txId))
    }

    func restore(mnemonic: String) -> [String: Any] {
        return callFFI(grin_wallet_restore(dataDir, password, nodeURL, mnemonic, network))
    }

    func nodeInfo() -> [String: Any] {
        return callFFI(grin_node_info(nodeURL))
    }

    func scanOutputs(startHeight: UInt64 = 0) -> [String: Any] {
        return callFFI(grin_wallet_scan(dataDir, password, nodeURL, startHeight))
    }

    func getOutputs(includeSpent: Bool = false) -> [String: Any] {
        return callFFI(grin_wallet_outputs(dataDir, password, nodeURL, includeSpent))
    }

    func getMnemonic() -> [String: Any] {
        return callFFI(grin_wallet_mnemonic(dataDir, password, nodeURL))
    }

    func scanProgress() -> UInt8 {
        return grin_wallet_scan_progress()
    }

    func getAddress() -> [String: Any] {
        return callFFI(grin_wallet_address(dataDir, password, nodeURL))
    }

    // MARK: - Invoice (RSR) API

    func issueInvoice(amount: Double) -> [String: Any] {
        let nanogrin = UInt64((amount * 1_000_000_000).rounded())
        return callFFI(grin_wallet_issue_invoice(dataDir, password, nodeURL, nanogrin))
    }

    func processInvoice(slatepack: String, minimumConfirmations: UInt64 = 10) -> [String: Any] {
        return callFFI(grin_wallet_process_invoice(dataDir, password, nodeURL, slatepack, minimumConfirmations))
    }

    func finalizeInvoice(responseSlatepack: String) -> [String: Any] {
        return callFFI(grin_wallet_finalize_invoice(dataDir, password, nodeURL, responseSlatepack))
    }
}
