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
//  PhoneToWatchService.swift
//  grin-ios
//
//  Sends wallet state to the watchOS companion app via WatchConnectivity.
//

import Foundation
import WatchConnectivity

class PhoneToWatchService: NSObject, WCSessionDelegate {
    static let shared = PhoneToWatchService()

    private var session: WCSession?

    /// Stored references so we can respond to watch pull-requests.
    private(set) var walletService: WalletService?
    private(set) var settings: AppSettings?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Wire up the service after the wallet is ready.
    func configure(walletService: WalletService, settings: AppSettings) {
        self.walletService = walletService
        self.settings = settings
    }

    // MARK: - Push wallet state to Watch

    func sendUpdate(
        balance: Double,
        balanceFiat: Double,
        currency: Currency,
        nodeStatus: NodeStatus,
        transactions: [Transaction]
    ) {
        guard let session, session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }

        // Encode transactions as JSON Data using Codable (matches WatchTransaction on the watch side)
        let watchTxs: [[String: Any]] = transactions.prefix(10).map { tx in
            [
                "numericId": tx.numericId,
                "direction": tx.direction.rawValue,
                "amount": tx.amount,
                "date": tx.date.timeIntervalSince1970,
                "status": tx.status.rawValue,
                "confirmations": tx.confirmations,
                "fee": tx.fee,
                "isInvoice": tx.isInvoice
            ]
        }

        let txData = try? JSONSerialization.data(withJSONObject: watchTxs)

        var payload: [String: Any] = [
            "balance": balance,
            "balanceFiat": balanceFiat,
            "currency": currency.rawValue,
            "currencySymbol": currency.symbol,
            "nodeStatus": nodeStatus.rawValue
        ]
        if let txData {
            payload["transactions"] = txData
        }

        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "walletUpdate" {
            guard let ws = walletService, let settings else {
                replyHandler([:])
                return
            }
            let balance = ws.balance
            let fiat = ws.balanceFiat(currency: settings.currency)
            let txs: [[String: Any]] = ws.transactions.prefix(10).map { tx in
                [
                    "numericId": tx.numericId,
                    "direction": tx.direction.rawValue,
                    "amount": tx.amount,
                    "date": tx.date.timeIntervalSince1970,
                    "status": tx.status.rawValue,
                    "confirmations": tx.confirmations,
                    "fee": tx.fee,
                    "isInvoice": tx.isInvoice
                ]
            }
            var reply: [String: Any] = [
                "balance": balance,
                "balanceFiat": fiat,
                "currency": settings.currency.rawValue,
                "currencySymbol": settings.currency.symbol,
                "nodeStatus": ws.nodeStatus.rawValue
            ]
            if let txData = try? JSONSerialization.data(withJSONObject: txs) {
                reply["transactions"] = txData
            }
            replyHandler(reply)
        }
    }
}
