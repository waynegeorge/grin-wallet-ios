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
//  SlatepackStore.swift
//  grin-ios
//
//  Persists slatepacks for incomplete transactions so they can be resumed.
//

import Foundation

class SlatepackStore {
    static let shared = SlatepackStore()

    private let key = "stored_slatepacks"

    private var store: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    enum SlateType: String {
        case initial          // SRS: sender's initial slatepack
        case response         // SRS: receiver's signed response
        case invoice          // RSR: receiver's invoice slatepack
        case invoiceResponse  // RSR: sender's processed response
    }

    func save(txId: Int, type: SlateType, slatepack: String) {
        var s = store
        s["\(txId)_\(type.rawValue)"] = slatepack
        store = s
    }

    func get(txId: Int, type: SlateType) -> String? {
        store["\(txId)_\(type.rawValue)"]
    }

    /// Returns true if any slatepack (initial, response, invoice, or invoiceResponse) is stored for this tx.
    func hasAny(txId: Int) -> Bool {
        let s = store
        let prefix = "\(txId)_"
        return s.keys.contains { $0.hasPrefix(prefix) }
    }

    func remove(txId: Int) {
        var s = store
        s.removeValue(forKey: "\(txId)_\(SlateType.initial.rawValue)")
        s.removeValue(forKey: "\(txId)_\(SlateType.response.rawValue)")
        s.removeValue(forKey: "\(txId)_\(SlateType.invoice.rawValue)")
        s.removeValue(forKey: "\(txId)_\(SlateType.invoiceResponse.rawValue)")
        store = s
    }

    // MARK: - RSR Invoice Tracking

    private let invoiceKey = "invoice_slate_ids"

    private var invoiceSlateIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: invoiceKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: invoiceKey) }
    }

    func markAsInvoice(slateId: String) {
        var ids = invoiceSlateIds
        ids.insert(slateId)
        invoiceSlateIds = ids
    }

    func isInvoice(slateId: String) -> Bool {
        invoiceSlateIds.contains(slateId)
    }
}
