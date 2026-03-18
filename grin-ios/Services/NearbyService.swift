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
//  NearbyService.swift
//  grin-ios
//

import Foundation
import MultipeerConnectivity

@Observable
class NearbyService: NSObject {
    var peers: [NearbyPeer] = []
    var isSearching: Bool = false
    var isAdvertising: Bool = false
    var receivedSlatepack: Slatepack?
    var receivedRawSlatepack: String?
    var sendingStatus: SendStatus = .idle
    var lastReceiveStatus: String?

    /// When true, suppresses auto-receive for the entire duration of a send flow.
    /// Set to true when starting a nearby send, reset to false only when the send
    /// sheet is dismissed — prevents the sender's wallet from auto-signing
    /// late-arriving or duplicate data on the session.
    var isSendFlowActive: Bool = false

    /// When true, the receiver is in invoice flow — store raw slatepack, don't auto-process.
    var isInvoiceFlowActive: Bool = false

    /// Pending approval request from a nearby peer
    var pendingRequest: NearbyRequest?

    /// Set this so incoming slatepacks can be auto-signed and returned
    var walletService: WalletService?

    enum SendStatus: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    /// A nearby transaction request awaiting user approval
    struct NearbyRequest {
        let peerName: String
        let peerID: MCPeerID
        let rawSlatepack: String
        let type: RequestType
        let session: MCSession
        let amount: Double?  // amount in grin, if known

        enum RequestType {
            case incomingSend      // SRS: someone wants to send us grin
            case incomingInvoice   // RSR: someone is requesting grin from us
        }
    }

    /// Message prefixes to distinguish slatepack types over nearby
    /// Format: "GRIN-INVOICE:amount:" or "GRIN-SRS:amount:"
    static let invoicePrefix = "GRIN-INVOICE:"
    static let srsPrefix = "GRIN-SRS:"

    private let serviceType = "grin-wallet"
    private var myPeerId: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        self.myPeerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    /// Update the display name used for peer discovery.
    /// Tears down existing connections and recreates with the new name.
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != myPeerId.displayName else { return }

        let wasAdvertising = isAdvertising
        let wasSearching = isSearching

        disconnect()
        myPeerId = MCPeerID(displayName: trimmed)

        if wasAdvertising || wasSearching {
            startAdvertising()
        }
        if wasSearching {
            startSearching()
        }
    }

    // MARK: - Always-On Advertising (receive mode)

    func startAdvertising() {
        guard !isAdvertising else { return }

        let session = self.session ?? createSession()

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    // MARK: - Browsing (find nearby wallets to send to)

    func startSearching() {
        guard !isSearching else { return }
        isSearching = true
        peers = []

        let session = self.session ?? createSession()

        let browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        // Also advertise while searching so both sides can find each other
        startAdvertising()
    }

    func stopSearching() {
        isSearching = false
        browser?.stopBrowsingForPeers()
        browser = nil
        // Keep advertising (always-on receive mode)
    }

    // MARK: - Session Management

    private func createSession() -> MCSession {
        let session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        return session
    }

    func disconnect() {
        stopSearching()
        stopAdvertising()
        session?.disconnect()
        session = nil
        peers = []
    }

    // MARK: - Send Slatepack

    /// Send an SRS slatepack to a nearby peer. Uses the raw string to preserve FFI formatting.
    func sendSlatepack(_ rawSlatepack: String, amount: Double, to peer: NearbyPeer) async {
        sendingStatus = .sending

        if let session, let mcPeer = session.connectedPeers.first(where: { $0.displayName == peer.displayName }) {
            do {
                let tagged = "\(Self.srsPrefix)\(amount):" + rawSlatepack
                let data = Data(tagged.utf8)
                try session.send(data, toPeers: [mcPeer], with: .reliable)
                sendingStatus = .sent
            } catch {
                sendingStatus = .failed(error.localizedDescription)
            }
        } else {
            sendingStatus = .failed("Peer not connected")
        }
        // Don't reset to .idle here — sendViaNearby controls the flow
        // and needs sendingStatus != .idle to prevent auto-signing the response
    }

    /// Send an RSR invoice slatepack to a nearby peer.
    func sendInvoice(_ rawSlatepack: String, amount: Double, to peer: NearbyPeer) async {
        sendingStatus = .sending

        if let session, let mcPeer = session.connectedPeers.first(where: { $0.displayName == peer.displayName }) {
            do {
                let tagged = "\(Self.invoicePrefix)\(amount):" + rawSlatepack
                let data = Data(tagged.utf8)
                try session.send(data, toPeers: [mcPeer], with: .reliable)
                sendingStatus = .sent
            } catch {
                sendingStatus = .failed(error.localizedDescription)
            }
        } else {
            sendingStatus = .failed("Peer not connected")
        }
    }

    func resetSendingStatus() {
        sendingStatus = .idle
    }

    /// Approve the pending nearby request — process and return response
    func approvePendingRequest() async {
        guard let request = pendingRequest, let walletService else {
            pendingRequest = nil
            return
        }

        switch request.type {
        case .incomingSend:
            // SRS: sign the slatepack and return response
            lastReceiveStatus = "Signing transaction…"
            if let responseSlatepack = await walletService.receiveSlatepack(request.rawSlatepack) {
                let responseData = Data(responseSlatepack.fullString.utf8)
                do {
                    try request.session.send(responseData, toPeers: [request.peerID], with: .reliable)
                    lastReceiveStatus = "Signed and returned"
                } catch {
                    lastReceiveStatus = "Failed to send response"
                }
            } else {
                lastReceiveStatus = "Failed to sign: \(walletService.errorMessage ?? "unknown error")"
            }

        case .incomingInvoice:
            // RSR: process the invoice and return response
            lastReceiveStatus = "Processing invoice…"
            if let invoiceResponse = await walletService.processInvoice(request.rawSlatepack) {
                let responseData = Data(invoiceResponse.fullString.utf8)
                do {
                    try request.session.send(responseData, toPeers: [request.peerID], with: .reliable)
                    lastReceiveStatus = "Invoice paid and returned"
                } catch {
                    lastReceiveStatus = "Failed to send response"
                }
                // Reset sendInProgress so refresh resumes — no SendView to do this
                walletService.sendInProgress = false
            } else {
                lastReceiveStatus = "Failed to process: \(walletService.errorMessage ?? "unknown error")"
            }
        }

        pendingRequest = nil
    }

    /// Reject the pending nearby request
    func rejectPendingRequest() {
        pendingRequest = nil
        lastReceiveStatus = "Transaction declined"
    }
}

// MARK: - MCSessionDelegate

extension NearbyService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if let index = self.peers.firstIndex(where: { $0.displayName == peerID.displayName }) {
                    self.peers[index].status = .connected
                } else {
                    // Peer connected via advertising (they found us)
                    self.peers.append(NearbyPeer(id: peerID.displayName, displayName: peerID.displayName, status: .connected))
                }
            case .connecting:
                if let index = self.peers.firstIndex(where: { $0.displayName == peerID.displayName }) {
                    self.peers[index].status = .connecting
                } else {
                    self.peers.append(NearbyPeer(id: peerID.displayName, displayName: peerID.displayName, status: .connecting))
                }
            case .notConnected:
                self.peers.removeAll { $0.displayName == peerID.displayName }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let string = String(data: data, encoding: .utf8) else { return }

            // Determine message type, extract amount and raw slatepack
            // Format: "GRIN-SRS:1.5:BEGINSLATEPACK..." or "GRIN-INVOICE:2.0:BEGINSLATEPACK..."
            let isInvoice = string.hasPrefix(Self.invoicePrefix)
            let isSRS = string.hasPrefix(Self.srsPrefix)
            let rawSlatepack: String
            var parsedAmount: Double? = nil

            if isInvoice || isSRS {
                let prefix = isInvoice ? Self.invoicePrefix : Self.srsPrefix
                let afterPrefix = String(string.dropFirst(prefix.count))
                // Extract amount between prefix and next ":"
                if let colonIndex = afterPrefix.firstIndex(of: ":") {
                    let amountStr = String(afterPrefix[afterPrefix.startIndex..<colonIndex])
                    parsedAmount = Double(amountStr)
                    rawSlatepack = String(afterPrefix[afterPrefix.index(after: colonIndex)...])
                } else {
                    rawSlatepack = afterPrefix
                }
            } else {
                // Untagged message — treat as a response (from older client or a reply)
                rawSlatepack = string
            }

            let service = SlatepackService.shared
            guard let parsed = await service.parse(rawSlatepack) else { return }

            // If we're in a send flow (active or waiting for response), store the RAW string — don't auto-sign.
            // isSendFlowActive stays true for the entire send sheet lifetime to prevent
            // late-arriving or duplicate packets from being auto-received by the sender's wallet.
            if self.isSendFlowActive || self.sendingStatus != .idle {
                self.receivedSlatepack = parsed
                self.receivedRawSlatepack = rawSlatepack
                return
            }

            // If we're in an invoice flow (waiting for sender's response), store raw — don't auto-process.
            if self.isInvoiceFlowActive {
                self.receivedSlatepack = parsed
                self.receivedRawSlatepack = rawSlatepack
                return
            }

            // Tagged messages require approval
            if isSRS {
                // SRS: someone wants to send us grin — ask user to accept
                self.pendingRequest = NearbyRequest(
                    peerName: peerID.displayName,
                    peerID: peerID,
                    rawSlatepack: rawSlatepack,
                    type: .incomingSend,
                    session: session,
                    amount: parsedAmount
                )
                return
            }

            if isInvoice {
                // RSR: someone is requesting grin from us — ask user to approve payment
                self.pendingRequest = NearbyRequest(
                    peerName: peerID.displayName,
                    peerID: peerID,
                    rawSlatepack: rawSlatepack,
                    type: .incomingInvoice,
                    session: session,
                    amount: parsedAmount
                )
                return
            }

            // Untagged message — store as received (likely a response to our send/invoice)
            self.receivedSlatepack = parsed
            self.receivedRawSlatepack = rawSlatepack
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NearbyService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Auto-accept all invitations
            invitationHandler(true, self.session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NearbyService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !self.peers.contains(where: { $0.displayName == peerID.displayName }) {
                self.peers.append(NearbyPeer(id: peerID.displayName, displayName: peerID.displayName, status: .found))
            }
            // Auto-invite found peers
            if let session = self.session {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.peers.removeAll { $0.displayName == peerID.displayName }
        }
    }
}
