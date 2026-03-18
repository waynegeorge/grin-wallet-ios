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
//  WalletService.swift
//  grin-ios
//

import Foundation
import os

@Observable
class WalletService {
    var nodeStatus: NodeStatus = .disconnected
    var nodeHeight: UInt64 = 0
    var walletInfo: WalletInfo?
    var transactions: [Transaction]
    var isLoading: Bool = false
    var errorMessage: String?
    var debugTxLog: String = ""
    /// When true, a send transaction is in-flight (init → finalize).
    /// Prevents background refreshes from touching the wallet DB.
    var sendInProgress: Bool = false
    /// When true, an invoice flow is in-flight (issue → finalize).
    var invoiceInProgress: Bool = false
    /// When true, a scan & repair is running.
    /// Blocks sends, receives, and refreshes to prevent DB corruption.
    var scanInProgress: Bool = false
    /// Set to true to cancel the scan. The FFI call continues in the background
    /// but the app unblocks and discards the result.
    var scanCancelled: Bool = false
    /// Node reachability during scan — updated by periodic health checks.
    var scanNodeReachable: Bool = true
    /// Scan progress percentage (0–100), polled from FFI during scan.
    var scanProgress: Int = 0

    /// Result of the last scan, set when scan completes. Nil while idle or in progress.
    var lastScanResult: ScanResult?

    enum ScanResult {
        case success(duration: String)
        case failed(duration: String, error: String)
    }

    private var _bridge: GrinWalletBridge?
    private var _bridgeNodeURL: String?
    private var _bridgeWalletName: String?

    private var bridge: GrinWalletBridge? {
        // Recreate bridge when node URL or active wallet changes
        let currentURL = settings.nodeBaseURL
        let currentWallet = WalletStore.shared.activeWallet
        if let existing = _bridge,
           _bridgeNodeURL == currentURL,
           _bridgeWalletName == currentWallet {
            return existing
        }
        guard let walletName = currentWallet,
              let password = WalletStore.shared.password(for: walletName) else {
            return nil
        }
        let newBridge = GrinWalletBridge(
            walletName: walletName,
            nodeURL: currentURL,
            password: password
        )
        _bridge = newBridge
        _bridgeNodeURL = currentURL
        _bridgeWalletName = walletName
        return newBridge
    }
    private let slatepackService = SlatepackService.shared

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        self.transactions = settings.lastKnownTransactions
    }

    // MARK: - Refresh

    /// Run a blocking FFI call on a background queue without timeout.
    /// Never use withTimeout on FFI calls — timed-out calls keep running and
    /// hold the Rust mutex, starving all subsequent wallet operations.
    private func asyncFFI<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = work()
                continuation.resume(returning: result)
            }
        }
    }

    func refresh() async {
        // Don't refresh while a send, scan, or another refresh is in-flight —
        // concurrent wallet DB access can corrupt stored blinding factors / nonces
        guard !sendInProgress, !scanInProgress, !invoiceInProgress, !isLoading else { return }

        guard let bridge else {
            errorMessage = "No wallet configured"
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        // Check node via HTTP (no FFI side effects)
        let nodeReachable = await checkNodeHTTP()

        if !nodeReachable {
            await MainActor.run {
                nodeStatus = .disconnected
                errorMessage = "Cannot connect to node"
                isLoading = false
            }
            return
        }

        await MainActor.run {
            nodeStatus = .connected
        }

        // Get balance
        let balanceResult = await asyncFFI {
            bridge.getBalance(minimumConfirmations: UInt64(self.settings.minimumConfirmations))
        }

        if !GrinWalletBridge.isError(balanceResult) {
            let total = balanceResult["total"] as? UInt64 ?? 0
            let spendable = balanceResult["spendable"] as? UInt64 ?? 0
            let immature = balanceResult["immature"] as? UInt64 ?? 0
            let locked = balanceResult["locked"] as? UInt64 ?? 0
            let awaitingConfirmation = balanceResult["awaiting_confirmation"] as? UInt64 ?? 0
            let awaitingFinalization = balanceResult["awaiting_finalization"] as? UInt64 ?? 0

            let totalGrin = nanoToGrin(total)
            await MainActor.run {
                walletInfo = WalletInfo(
                    lastConfirmedHeight: 0,
                    minimumConfirmations: UInt64(settings.minimumConfirmations),
                    totalBalance: totalGrin,
                    amountAwaitingConfirmation: nanoToGrin(awaitingConfirmation),
                    amountAwaitingFinalization: nanoToGrin(awaitingFinalization),
                    amountCurrentlySpendable: nanoToGrin(spendable),
                    amountImmature: nanoToGrin(immature),
                    amountLocked: nanoToGrin(locked)
                )
                settings.lastKnownBalance = totalGrin
            }
        }

        // Get transactions
        let txResult = await asyncFFI {
            bridge.getTransactions()
        }

        if !GrinWalletBridge.isError(txResult),
           let txArray = txResult["txs"] as? [[String: Any]] {
            // DEBUG: capture raw FFI tx data
            let debugLines = txArray.map { "\($0)" }.joined(separator: "\n---\n")
            await MainActor.run { debugTxLog = debugLines }
            var parsed = txArray.compactMap { parseTx($0) }
                .sorted { $0.date > $1.date }

            // Enrich transactions with output data — restored/scanned txs often
            // lack kernel_excess and kernel_lookup_min_height, so we use the
            // output's block height (linked via tx_log_entry) to fill in gaps.
            // Fetch outputs and mempool kernels in parallel to avoid blocking
            async let outputsFetch = getOutputs(includeSpent: true)
            async let mempoolFetch = getMempoolKernels()
            let outputs = await outputsFetch
            let mempoolKernels = await mempoolFetch

            var txIdToOutputHeight: [Int: UInt64] = [:]
            for output in outputs where output.height > 0 {
                if let entry = output.txLogEntry {
                    // Keep the highest output height per tx (most accurate)
                    if let existing = txIdToOutputHeight[entry] {
                        txIdToOutputHeight[entry] = max(existing, output.height)
                    } else {
                        txIdToOutputHeight[entry] = output.height
                    }
                }
            }

            let minConf = settings.minimumConfirmations
            for i in parsed.indices {
                let tx = parsed[i]

                // Try to fill in block height from outputs if missing
                var resolvedHeight = tx.blockHeight
                if resolvedHeight == nil || resolvedHeight == 0 {
                    if let outputHeight = txIdToOutputHeight[tx.numericId] {
                        resolvedHeight = Int(outputHeight)
                    }
                }

                // Recalculate confirmations from resolved height
                var resolvedConfirmations = tx.confirmations
                if let bh = resolvedHeight, bh > 0, nodeHeight >= UInt64(bh) {
                    resolvedConfirmations = Int(1 + nodeHeight - UInt64(bh))
                }

                // Estimate original date from block height for restored txs
                // (creation_ts is set to scan time, not original tx time)
                var resolvedDate = tx.date
                if let bh = resolvedHeight, bh > 0, !settings.heightCalibration.isEmpty {
                    // Reverse-estimate date from block height using calibration
                    let estimatedDate = estimateDateFromHeight(UInt64(bh))
                    if let est = estimatedDate {
                        resolvedDate = est
                    }
                }

                // 3-state resolution:
                //  - No kernel → exchange never completed → .incomplete
                //  - Kernel on-chain → .confirmed (with real height & confirmations from kernel)
                //  - Kernel exists but not on-chain → .confirming (broadcast, awaiting mining)
                //  - Already confirmed by wallet → enrich with output data if needed
                let hasKernel: Bool
                if let ke = tx.kernelExcess, !ke.isEmpty {
                    // Filter out placeholder/zero kernels that appear on incomplete txs.
                    // A valid Pedersen commitment is 66 hex chars (33 bytes) and is never all-zeros.
                    let isAllZeros = ke.allSatisfy { $0 == "0" }
                    hasKernel = !isAllZeros
                } else {
                    hasKernel = false
                }

                if tx.status != .confirmed && !hasKernel {
                    // No kernel = interactive exchange never completed
                    parsed[i] = Transaction(
                        numericId: tx.numericId,
                        direction: tx.direction,
                        amount: tx.amount,
                        date: resolvedDate,
                        status: .incomplete,
                        confirmations: 0,
                        blockHeight: nil,
                        fee: tx.fee,
                        txId: tx.txId,
                        kernelExcess: tx.kernelExcess,
                        slateId: tx.slateId,
                        txType: tx.txType,
                        isInvoice: tx.isInvoice
                    )
                } else if tx.status != .confirmed && hasKernel {
                    // Has kernel — check chain for authoritative height
                    if let minedHeight = await getKernelHeight(tx.kernelExcess!) {
                        let realConfirmations = nodeHeight >= minedHeight
                            ? Int(1 + nodeHeight - minedHeight) : 1
                        parsed[i] = Transaction(
                            numericId: tx.numericId,
                            direction: tx.direction,
                            amount: tx.amount,
                            date: resolvedDate,
                            status: .confirmed,
                            confirmations: realConfirmations,
                            blockHeight: Int(minedHeight),
                            fee: tx.fee,
                            txId: tx.txId,
                            kernelExcess: tx.kernelExcess,
                            slateId: tx.slateId,
                            txType: tx.txType,
                            isInvoice: tx.isInvoice
                        )
                    } else {
                        // Kernel not on-chain yet. Check mempool for authoritative state.
                        let inMempool = mempoolKernels.contains(tx.kernelExcess!)
                        let status: TransactionStatus
                        if inMempool {
                            // In mempool = finalized & broadcast, awaiting mining
                            status = .confirming
                        } else if !mempoolKernels.isEmpty {
                            // Mempool was fetched successfully but kernel not there = still exchanging
                            status = .incomplete
                        } else {
                            // Mempool fetch failed — fall back to SlatepackStore discriminator
                            let stillExchanging = SlatepackStore.shared.hasAny(txId: tx.numericId)
                            status = stillExchanging ? .incomplete : .confirming
                        }
                        parsed[i] = Transaction(
                            numericId: tx.numericId,
                            direction: tx.direction,
                            amount: tx.amount,
                            date: resolvedDate,
                            status: status,
                            confirmations: 0,
                            blockHeight: nil,
                            fee: tx.fee,
                            txId: tx.txId,
                            kernelExcess: tx.kernelExcess,
                            slateId: tx.slateId,
                            txType: tx.txType,
                            isInvoice: tx.isInvoice
                        )
                    }
                } else if tx.status == .confirmed && hasKernel {
                    // Always use kernel lookup for authoritative mined height.
                    // kernel_lookup_min_height (from parseTx) is the creation height,
                    // NOT the mined block — it drifts by 1-2 blocks.
                    if let minedHeight = await getKernelHeight(tx.kernelExcess!) {
                        let realConfirmations = nodeHeight >= minedHeight
                            ? Int(1 + nodeHeight - minedHeight) : 1
                        parsed[i] = Transaction(
                            numericId: tx.numericId,
                            direction: tx.direction,
                            amount: tx.amount,
                            date: resolvedDate,
                            status: .confirmed,
                            confirmations: realConfirmations,
                            blockHeight: Int(minedHeight),
                            fee: tx.fee,
                            txId: tx.txId,
                            kernelExcess: tx.kernelExcess,
                            slateId: tx.slateId,
                            txType: tx.txType,
                            isInvoice: tx.isInvoice
                        )
                    } else if resolvedHeight != tx.blockHeight || resolvedConfirmations != tx.confirmations || resolvedDate != tx.date {
                        // Kernel lookup failed — fall back to output-derived data
                        parsed[i] = Transaction(
                            numericId: tx.numericId,
                            direction: tx.direction,
                            amount: tx.amount,
                            date: resolvedDate,
                            status: tx.status,
                            confirmations: resolvedConfirmations,
                            blockHeight: resolvedHeight,
                            fee: tx.fee,
                            txId: tx.txId,
                            kernelExcess: tx.kernelExcess,
                            slateId: tx.slateId,
                            txType: tx.txType,
                            isInvoice: tx.isInvoice
                        )
                    }
                } else if resolvedHeight != tx.blockHeight || resolvedConfirmations != tx.confirmations || resolvedDate != tx.date {
                    // Confirmed tx without kernel — enrich with output-derived data
                    parsed[i] = Transaction(
                        numericId: tx.numericId,
                        direction: tx.direction,
                        amount: tx.amount,
                        date: resolvedDate,
                        status: tx.status,
                        confirmations: resolvedConfirmations,
                        blockHeight: resolvedHeight,
                        fee: tx.fee,
                        txId: tx.txId,
                        kernelExcess: tx.kernelExcess,
                        slateId: tx.slateId,
                        txType: tx.txType,
                        isInvoice: tx.isInvoice
                    )
                }
            }

            await MainActor.run {
                transactions = parsed
                settings.lastKnownTransactions = parsed
            }
        }

        // Clean up stored slatepacks for confirmed/cancelled txs
        cleanUpStoredSlatepacks()

        // Push latest state to Apple Watch companion
        await MainActor.run {
            PhoneToWatchService.shared.sendUpdate(
                balance: balance,
                balanceFiat: balanceFiat(currency: settings.currency),
                currency: settings.currency,
                nodeStatus: nodeStatus,
                transactions: transactions
            )
        }

        await MainActor.run {
            isLoading = false
        }

        // Calibrate height↔timestamp mapping on first successful load
        if settings.heightCalibration.isEmpty && nodeHeight > 0 {
            await calibrateHeightSamples()
        }
    }

    // MARK: - Node Check (HTTP)

    private func checkNodeHTTP() async -> Bool {
        guard let url = URL(string: settings.foreignNodeURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "get_tip",
            "params": []
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let ok = result["Ok"] as? [String: Any],
               let height = ok["height"] as? UInt64 {
                await MainActor.run { nodeHeight = height }
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Height Calibration

    /// Sample block headers at regular intervals to build a height↔timestamp mapping.
    /// Called once on first launch (or when calibration data is empty).
    func calibrateHeightSamples() async {
        guard settings.heightCalibration.isEmpty else { return }
        guard nodeHeight > 0 else { return }

        let tipHeight = nodeHeight
        // Sample ~10 points evenly across the chain, plus the tip
        let step = max(tipHeight / 10, 1)
        var samples: [[Double]] = []

        var height: UInt64 = 1
        while height < tipHeight {
            if let timestamp = await getBlockTimestamp(height: height) {
                samples.append([Double(height), timestamp])
            }
            height += step
        }
        // Always include the tip
        if let timestamp = await getBlockTimestamp(height: tipHeight) {
            samples.append([Double(tipHeight), timestamp])
        }

        guard samples.count >= 2 else { return }
        await MainActor.run {
            settings.heightCalibration = samples
        }
    }

    /// Query the node for a block header's timestamp at a given height.
    private func getBlockTimestamp(height: UInt64) async -> Double? {
        guard let url = URL(string: settings.foreignNodeURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "get_header",
            "params": [height, nil, nil] as [Any?]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let ok = result["Ok"] as? [String: Any],
               let header = ok["header"] as? [String: Any],
               let timestamp = header["timestamp"] as? String {
                // Grin timestamps are RFC3339: "2019-01-15T16:01:26+00:00"
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: timestamp) {
                    return date.timeIntervalSince1970
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Kernel Verification

    /// Fetch kernel excesses from the node's mempool (unconfirmed transactions).
    /// Returns a set of hex-encoded kernel excess strings, or an empty set on failure.
    private func getMempoolKernels() async -> Set<String> {
        let endpoint = settings.foreignNodeURL
        guard let url = URL(string: endpoint) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "get_unconfirmed_transactions",
            "params": [] as [Any]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

            // Save raw response for debugging (visible in advanced mode)
            let rawString = String(data: data, encoding: .utf8) ?? ""
            await MainActor.run {
                debugTxLog += "\n\n[MEMPOOL RAW] \(String(rawString.prefix(3000)))"
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let txs = result["Ok"] as? [[String: Any]] else { return [] }

            var kernels = Set<String>()
            for tx in txs {
                // Try both "tx_at_commit_time" and "tx" paths (PoolEntry has both)
                let txObjects = [tx["tx_at_commit_time"], tx["tx"]].compactMap { $0 as? [String: Any] }
                for txObj in txObjects {
                    if let body = txObj["body"] as? [String: Any],
                       let txKernels = body["kernels"] as? [[String: Any]] {
                        for kernel in txKernels {
                            if let excess = kernel["excess"] as? String {
                                kernels.insert(excess)
                            }
                        }
                    }
                }
            }

            await MainActor.run {
                debugTxLog += "\n[MEMPOOL KERNELS] \(kernels)"
            }
            return kernels
        } catch {
            return []
        }
    }

    /// Look up a kernel on-chain and return the block height it was mined in, or nil if not found.
    private func getKernelHeight(_ kernel: String) async -> UInt64? {
        let endpoint = settings.foreignNodeURL
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "get_kernel",
            "params": [kernel, nil, nil] as [Any?]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let ok = result["Ok"] as? [String: Any],
               let height = ok["height"] as? UInt64 {
                return height
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Date from Height

    /// Reverse-estimate a date from a block height using calibration samples.
    /// Returns nil if no calibration data is available.
    private func estimateDateFromHeight(_ height: UInt64) -> Date? {
        let samples = settings.heightCalibration
        guard samples.count >= 2 else { return nil }

        let h = Double(height)

        // Before first sample — extrapolate
        if h <= samples.first![0] {
            let s0 = samples[0]
            let s1 = samples[1]
            let rate = (s1[1] - s0[1]) / (s1[0] - s0[0]) // seconds per block
            let t = s0[1] + rate * (h - s0[0])
            return Date(timeIntervalSince1970: t)
        }

        // After last sample — extrapolate
        if h >= samples.last![0] {
            let s0 = samples[samples.count - 2]
            let s1 = samples[samples.count - 1]
            let rate = (s1[1] - s0[1]) / (s1[0] - s0[0])
            let t = s1[1] + rate * (h - s1[0])
            return Date(timeIntervalSince1970: t)
        }

        // Interpolate between bracketing samples
        for i in 0..<(samples.count - 1) {
            let s0 = samples[i]
            let s1 = samples[i + 1]
            if h >= s0[0] && h <= s1[0] {
                let fraction = (h - s0[0]) / (s1[0] - s0[0])
                let t = s0[1] + fraction * (s1[1] - s0[1])
                return Date(timeIntervalSince1970: t)
            }
        }

        return nil
    }

    // MARK: - Fee Estimation

    func estimateFee(amount: Double) async -> Double? {
        guard bridge != nil else { return nil }

        // Count spendable outputs to estimate the number of inputs.
        // The wallet selects outputs to cover (amount + fee), so for a max send
        // it will typically consume all spendable outputs.
        let outputs = await getOutputs(includeSpent: false)
        let spendableOutputs = outputs.filter { $0.status == .unspent }

        // Estimate inputs needed: accumulate outputs by value until we cover amount.
        // For max sends this will be all of them.
        let amountNano = UInt64((amount * 1_000_000_000).rounded())
        let sorted = spendableOutputs.sorted { $0.value > $1.value }
        var accumulated: UInt64 = 0
        var numInputs = 0
        for output in sorted {
            accumulated += output.value
            numInputs += 1
            // Rough check: once we've covered amount + a generous fee estimate, stop
            if accumulated >= amountNano + UInt64(numInputs + 45) * 500_000 {
                break
            }
        }
        // At minimum 1 input
        numInputs = max(numInputs, 1)

        // Fee = (num_inputs * 1 + num_outputs * 21 + num_kernels * 3) * 500,000 nanogrin
        // Typical tx: numInputs inputs, 2 outputs (recipient + change), 1 kernel
        let feeNano = UInt64(numInputs + 45) * 500_000
        return nanoToGrin(feeNano)
    }

    // MARK: - Send

    func initiateSend(amount: Double) async -> Slatepack? {
        guard !scanInProgress else {
            errorMessage = "Cannot send while scan is in progress"
            return nil
        }
        guard let bridge else { return nil }

        isLoading = true
        sendInProgress = true
        defer { isLoading = false }

        let result = bridge.initSend(amount: amount, minimumConfirmations: UInt64(settings.minimumConfirmations))
        if let error = GrinWalletBridge.errorMessage(result) {
            errorMessage = error
            sendInProgress = false
            return nil
        }

        guard let slatepackStr = result["slatepack"] as? String else {
            errorMessage = "No slatepack returned"
            sendInProgress = false
            return nil
        }

        // Persist the initial slatepack so the sender can re-share if finalize fails
        if let txId = findNewestIncompleteTxId(direction: "Sent") {
            SlatepackStore.shared.save(txId: txId, type: .initial, slatepack: slatepackStr)
        }

        // Parse for display but preserve the raw FFI string
        return await slatepackService.parse(slatepackStr)
    }

    // MARK: - Receive

    func receiveSlatepack(_ slatepackString: String) async -> Slatepack? {
        guard !scanInProgress else {
            errorMessage = "Cannot receive while scan is in progress"
            return nil
        }
        guard let bridge else { return nil }

        isLoading = true
        defer { isLoading = false }

        // Pass the raw string directly to FFI — do not reconstruct
        let result = bridge.receive(slatepack: slatepackString)
        if let error = GrinWalletBridge.errorMessage(result) {
            errorMessage = error
            return nil
        }

        guard let responseStr = result["slatepack"] as? String else {
            errorMessage = "No response slatepack returned"
            return nil
        }

        // Persist the response slatepack so the receiver can re-share if sender's finalize fails
        if let txId = findNewestIncompleteTxId(direction: "Received") {
            SlatepackStore.shared.save(txId: txId, type: .response, slatepack: responseStr)
        }

        // Parse for display but rawString preserves FFI output exactly
        return await slatepackService.parse(responseStr)
    }

    // MARK: - Finalize

    func finalizeTransaction(_ slatepackString: String) async -> Bool {
        guard let bridge else {
            errorMessage = "No wallet configured"
            sendInProgress = false
            return false
        }

        guard !slatepackString.isEmpty else {
            errorMessage = "Empty response slatepack"
            sendInProgress = false
            return false
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        // Debug: log what we're sending to finalize
        debugTxLog = "FINALIZE INPUT (len=\(slatepackString.count)):\n\(slatepackString.prefix(200))…"

        let result = await asyncFFI {
            bridge.finalize(responseSlatepack: slatepackString)
        }

        // Debug: log result
        await MainActor.run {
            debugTxLog += "\n\nFINALIZE RESULT: \(result)"
        }

        // Send flow complete — allow refreshes again
        await MainActor.run {
            isLoading = false
            sendInProgress = false
        }

        if let error = GrinWalletBridge.errorMessage(result) {
            await MainActor.run {
                errorMessage = "Finalize error: \(error)"
            }
            return false
        }

        let finalized = result["finalized"] as? Bool ?? false
        if finalized {
            // Clean up stored slatepacks for this completed transaction
            cleanUpStoredSlatepacks()
        } else {
            await MainActor.run {
                errorMessage = "Finalize returned: \(result)"
            }
        }
        return finalized
    }

    // MARK: - Invoice (RSR)

    func issueInvoice(amount: Double) async -> Slatepack? {
        guard !scanInProgress else {
            errorMessage = "Cannot create invoice while scan is in progress"
            return nil
        }
        guard let bridge else { return nil }

        isLoading = true
        invoiceInProgress = true
        defer { isLoading = false }

        let result = bridge.issueInvoice(amount: amount)
        if let error = GrinWalletBridge.errorMessage(result) {
            errorMessage = error
            invoiceInProgress = false
            return nil
        }

        guard let slatepackStr = result["slatepack"] as? String else {
            errorMessage = "No slatepack returned"
            invoiceInProgress = false
            return nil
        }

        // Persist the invoice slatepack so the invoicer can re-share
        if let txId = findNewestIncompleteTxId(direction: "Received") {
            SlatepackStore.shared.save(txId: txId, type: .invoice, slatepack: slatepackStr)
            // Find the slate ID from the tx log to mark as invoice
            let txResult = bridge.getTransactions()
            if !GrinWalletBridge.isError(txResult),
               let txArray = txResult["txs"] as? [[String: Any]],
               let tx = txArray.first(where: { ($0["id"] as? Int) == txId }),
               let slateId = tx["tx_slate_id"] as? String {
                SlatepackStore.shared.markAsInvoice(slateId: slateId)
            }
        }

        return await slatepackService.parse(slatepackStr)
    }

    func processInvoice(_ slatepackString: String) async -> Slatepack? {
        guard !scanInProgress else {
            errorMessage = "Cannot pay invoice while scan is in progress"
            return nil
        }
        guard let bridge else { return nil }

        isLoading = true
        sendInProgress = true
        defer { isLoading = false }

        let result = bridge.processInvoice(slatepack: slatepackString, minimumConfirmations: UInt64(settings.minimumConfirmations))
        if let error = GrinWalletBridge.errorMessage(result) {
            errorMessage = error
            sendInProgress = false
            return nil
        }

        guard let responseStr = result["slatepack"] as? String else {
            errorMessage = "No response slatepack returned"
            sendInProgress = false
            return nil
        }

        // Persist the response slatepack
        if let txId = findNewestIncompleteTxId(direction: "Sent") {
            SlatepackStore.shared.save(txId: txId, type: .invoiceResponse, slatepack: responseStr)
            let txResult = bridge.getTransactions()
            if !GrinWalletBridge.isError(txResult),
               let txArray = txResult["txs"] as? [[String: Any]],
               let tx = txArray.first(where: { ($0["id"] as? Int) == txId }),
               let slateId = tx["tx_slate_id"] as? String {
                SlatepackStore.shared.markAsInvoice(slateId: slateId)
            }
        }

        return await slatepackService.parse(responseStr)
    }

    func finalizeInvoice(_ slatepackString: String) async -> Bool {
        guard let bridge else {
            errorMessage = "No wallet configured"
            invoiceInProgress = false
            return false
        }

        guard !slatepackString.isEmpty else {
            errorMessage = "Empty response slatepack"
            invoiceInProgress = false
            return false
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let result = await asyncFFI {
            bridge.finalizeInvoice(responseSlatepack: slatepackString)
        }

        await MainActor.run {
            isLoading = false
            invoiceInProgress = false
        }

        if let error = GrinWalletBridge.errorMessage(result) {
            await MainActor.run {
                errorMessage = "Finalize error: \(error)"
            }
            return false
        }

        let finalized = result["finalized"] as? Bool ?? false
        if finalized {
            cleanUpStoredSlatepacks()
        } else {
            await MainActor.run {
                errorMessage = "Finalize returned: \(result)"
            }
        }
        return finalized
    }

    // MARK: - Scan/Repair

    func scanAndRepair(startHeight: UInt64 = 0) async -> Bool {
        let scanStart = Date()
        guard let bridge else { return false }
        guard !sendInProgress else {
            await MainActor.run { errorMessage = "Cannot scan while a send is in progress" }
            return false
        }

        await MainActor.run {
            isLoading = true
            scanInProgress = true
            scanCancelled = false
            scanNodeReachable = true
            scanProgress = 0
            lastScanResult = nil
        }

        // Start periodic node health checks and progress polling while the scan runs
        let healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let reachable = await checkNodeHTTP()
                let progress = Int(bridge.scanProgress())
                await MainActor.run {
                    scanNodeReachable = reachable
                    scanProgress = progress
                }
            }
        }

        // Run without timeout — scan can take minutes on large wallets,
        // and timed-out FFI calls keep running and hold the Rust mutex.
        let result: [String: Any] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = bridge.scanOutputs(startHeight: startHeight)
                continuation.resume(returning: r)
            }
        }

        healthCheckTask.cancel()

        let wasCancelled = scanCancelled
        let isError = GrinWalletBridge.isError(result)

        // Show final progress before clearing the UI
        let finalProgress = Int(bridge.scanProgress())
        await MainActor.run {
            scanProgress = isError ? finalProgress : 100
        }

        // Brief pause so the user sees the final progress
        try? await Task.sleep(for: .milliseconds(500))

        let elapsed = Date().timeIntervalSince(scanStart)
        let durationStr = elapsed >= 60
            ? String(format: "%dm %ds", Int(elapsed) / 60, Int(elapsed) % 60)
            : String(format: "%ds", Int(elapsed))

        // If the user cancelled, discard the result
        if wasCancelled {
            await MainActor.run {
                isLoading = false
                scanInProgress = false
                scanCancelled = false
                scanNodeReachable = true
                scanProgress = 0
            }
            return false
        }

        if isError {
            let errorMsg = GrinWalletBridge.errorMessage(result) ?? "Unknown error"
            await MainActor.run {
                errorMessage = errorMsg
                lastScanResult = .failed(duration: durationStr, error: errorMsg)
                isLoading = false
                scanInProgress = false
                scanNodeReachable = true
                scanProgress = 0
            }
            return false
        }

        await MainActor.run {
            scanNodeReachable = true
        }

        await refresh()

        await MainActor.run {
            lastScanResult = .success(duration: durationStr)
            isLoading = false
            scanInProgress = false
            scanProgress = 0
        }

        return true
    }

    func cancelScan() {
        scanCancelled = true
        scanInProgress = false
        isLoading = false
    }

    // MARK: - Cancel

    func cancelTransaction(numericId: Int) async {
        guard let bridge else { return }

        let result = await asyncFFI {
            bridge.cancel(txId: UInt32(numericId))
        }

        if GrinWalletBridge.isError(result) {
            await MainActor.run {
                errorMessage = GrinWalletBridge.errorMessage(result)
            }
        }

        // Clean up any stored slatepacks for the cancelled transaction
        SlatepackStore.shared.remove(txId: numericId)

        // Refresh to update the list
        await refresh()
    }

    // MARK: - Slatepack Persistence

    /// Find the newest unconfirmed tx matching a direction, to link a slatepack to its tx ID.
    /// Called right after initiateSend/receiveSlatepack when the wallet DB has the new entry.
    private func findNewestIncompleteTxId(direction: String) -> Int? {
        guard let bridge else { return nil }
        let result = bridge.getTransactions()
        guard !GrinWalletBridge.isError(result),
              let txArray = result["txs"] as? [[String: Any]] else { return nil }

        // Find the newest unconfirmed tx matching the direction
        return txArray
            .filter { dict in
                let typeStr = dict["tx_type"] as? String ?? ""
                let confirmed = (dict["confirmed"] as? Int ?? 0) != 0
                return !confirmed && typeStr.contains(direction)
            }
            .compactMap { $0["id"] as? Int }
            .max()
    }

    /// Get a stored slatepack for a transaction.
    func storedSlatepack(txId: Int, type: SlatepackStore.SlateType) -> String? {
        SlatepackStore.shared.get(txId: txId, type: type)
    }

    /// Clean up stored slatepacks for transactions that are confirmed or cancelled.
    private func cleanUpStoredSlatepacks() {
        guard let bridge else { return }
        let result = bridge.getTransactions()
        guard !GrinWalletBridge.isError(result),
              let txArray = result["txs"] as? [[String: Any]] else { return }

        let finishedIds = txArray
            .filter { dict in
                let confirmed = (dict["confirmed"] as? Int ?? 0) != 0
                let typeStr = dict["tx_type"] as? String ?? ""
                let cancelled = typeStr.contains("Cancelled") || typeStr.contains("Canceled")
                return confirmed || cancelled
            }
            .compactMap { $0["id"] as? Int }

        for id in finishedIds {
            SlatepackStore.shared.remove(txId: id)
        }
    }

    // MARK: - Recovery Phrase

    func getRecoveryPhrase() async -> String? {
        guard let bridge else { return nil }

        let result = await asyncFFI {
            bridge.getMnemonic()
        }

        if GrinWalletBridge.isError(result) {
            await MainActor.run {
                errorMessage = GrinWalletBridge.errorMessage(result)
            }
            return nil
        }

        return result["mnemonic"] as? String
    }

    // MARK: - Outputs

    func getOutputs(includeSpent: Bool = false) async -> [WalletOutput] {
        guard let bridge else { return [] }

        let result = bridge.getOutputs(includeSpent: includeSpent)

        guard !GrinWalletBridge.isError(result),
              let outputsArray = result["outputs"] as? [[String: Any]] else {
            return []
        }

        return outputsArray.compactMap { dict in
            guard let commit = dict["commit"] as? String,
                  let statusStr = dict["status"] as? String else { return nil }

            let value: UInt64
            if let v = dict["value"] as? UInt64 {
                value = v
            } else if let v = dict["value"] as? Int {
                value = UInt64(v)
            } else if let v = dict["value"] as? Double {
                value = UInt64(v)
            } else {
                value = 0
            }

            let status: OutputStatus
            switch statusStr {
            case "Unconfirmed": status = .unconfirmed
            case "Unspent": status = .unspent
            case "Locked": status = .locked
            case "Spent": status = .spent
            case "Reverted": status = .reverted
            default: status = .unconfirmed
            }

            let height: UInt64
            if let h = dict["height"] as? UInt64 { height = h }
            else if let h = dict["height"] as? Int { height = UInt64(h) }
            else { height = 0 }

            let lockHeight: UInt64
            if let h = dict["lock_height"] as? UInt64 { lockHeight = h }
            else if let h = dict["lock_height"] as? Int { lockHeight = UInt64(h) }
            else { lockHeight = 0 }

            let isCoinbase = dict["is_coinbase"] as? Bool ?? false

            let txLogEntry: Int?
            if let t = dict["tx_log_entry"] as? Int { txLogEntry = t }
            else { txLogEntry = nil }

            let nChild: Int
            if let n = dict["n_child"] as? Int { nChild = n }
            else { nChild = 0 }

            let mmrIndex: UInt64?
            if let m = dict["mmr_index"] as? UInt64 { mmrIndex = m }
            else if let m = dict["mmr_index"] as? Int { mmrIndex = UInt64(m) }
            else { mmrIndex = nil }

            return WalletOutput(
                commit: commit,
                value: value,
                status: status,
                height: height,
                lockHeight: lockHeight,
                isCoinbase: isCoinbase,
                txLogEntry: txLogEntry,
                nChild: nChild,
                mmrIndex: mmrIndex
            )
        }
    }

    // MARK: - Split Outputs (Self-Send)

    /// Split the largest UTXO into smaller pieces via self-send.
    /// Each iteration sends `amount` to self, creating two new outputs (amount + change).
    func splitOutputs(pieces: Int) async -> Bool {
        guard pieces >= 2 else { return false }
        guard let bridge else {
            errorMessage = "No wallet configured"
            return false
        }
        guard !scanInProgress, !sendInProgress, !invoiceInProgress else {
            errorMessage = "Another operation is in progress"
            return false
        }

        await MainActor.run {
            sendInProgress = true
            isLoading = true
            errorMessage = nil
        }

        // Fee for a typical tx: (1 input + 2 outputs + 1 kernel) * 500,000 = 23,000,000 nanogrin
        let feeEstimate: UInt64 = 23_000_000
        let splits = min(pieces - 1, 7) // max 7 self-sends (creating 8 outputs)
        var success = true

        for i in 0..<splits {
            let bal = bridge.getBalance(minimumConfirmations: 1)
            let currentSpendable = bal["spendable"] as? UInt64 ?? 0
            guard currentSpendable > feeEstimate * 2 else {
                await MainActor.run { errorMessage = "Insufficient funds for split \(i + 1)" }
                success = false
                break
            }

            let splitAmount = (currentSpendable - feeEstimate) / UInt64(splits - i + 1)
            guard splitAmount > 0 else { break }

            let amountGrin = Double(splitAmount) / 1_000_000_000.0

            // Self-send: initSend → receive → finalize
            let sendResult = bridge.initSend(amount: amountGrin, minimumConfirmations: 1)
            guard let slatepack = sendResult["slatepack"] as? String,
                  !GrinWalletBridge.isError(sendResult) else {
                await MainActor.run { errorMessage = "Split \(i + 1) initSend failed" }
                success = false
                break
            }

            let recvResult = bridge.receive(slatepack: slatepack)
            guard let response = recvResult["slatepack"] as? String,
                  !GrinWalletBridge.isError(recvResult) else {
                await MainActor.run { errorMessage = "Split \(i + 1) receive failed" }
                success = false
                break
            }

            let finalResult = bridge.finalize(responseSlatepack: response)
            let finalized = finalResult["finalized"] as? Bool ?? false
            if !finalized {
                await MainActor.run { errorMessage = "Split \(i + 1) finalize failed" }
                success = false
                break
            }
        }

        await MainActor.run {
            sendInProgress = false
            isLoading = false
        }

        await refresh()
        return success
    }

    // MARK: - Balance Helpers

    var balance: Double {
        guard let info = walletInfo else { return settings.lastKnownBalance }
        // Spendable + awaiting confirmation gives accurate "what I own" without double-counting locked outputs
        return info.amountCurrentlySpendable + info.amountAwaitingConfirmation
    }

    var spendableBalance: Double {
        walletInfo?.amountCurrentlySpendable ?? 0
    }

    func balanceFiat(currency: Currency) -> Double {
        // Placeholder: zero on testnet, replace with real exchange rate for mainnet
        let grinPrice: Double
        switch currency {
        case .usd: grinPrice = 0
        case .gbp: grinPrice = 0
        case .eur: grinPrice = 0
        }
        return balance * grinPrice
    }

    // MARK: - Helpers

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",      // 2026-03-06T15:10:00.000000+00:00
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSX",       // with timezone offset variant
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",        // no timezone
            "yyyy-MM-dd'T'HH:mm:ssZ",              // no fractional seconds
            "yyyy-MM-dd'T'HH:mm:ss",               // bare
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            return df
        }
    }()

    private static func parseDate(_ string: String) -> Date? {
        // Try ISO8601 with fractional seconds first
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }

        // Try without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        // Fall back to DateFormatter variants
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private func nanoToGrin(_ nano: UInt64) -> Double {
        Double(nano) / 1_000_000_000.0
    }

    private func parseTx(_ dict: [String: Any]) -> Transaction? {
        guard let idNum = dict["id"] as? Int,
              let typeStr = dict["tx_type"] as? String else {
            return nil
        }

        // Skip cancelled transactions
        if typeStr.contains("Cancelled") || typeStr.contains("Canceled") {
            return nil
        }

        let direction: TransactionDirection = typeStr.contains("Sent") ? .sent : .received
        let amountCredited = dict["amount_credited"] as? String ?? "0"
        let amountDebited = dict["amount_debited"] as? String ?? "0"
        let feeStr = dict["fee"] as? String ?? "0"
        let credited = UInt64(amountCredited) ?? 0
        let debited = UInt64(amountDebited) ?? 0
        let feeNano = UInt64(feeStr) ?? 0
        let amount: Double
        if direction == .received {
            amount = nanoToGrin(credited)
        } else {
            let net = Int64(debited) - Int64(credited) - Int64(feeNano)
            amount = nanoToGrin(UInt64(max(net, 0)))
        }

        // FFI returns confirmed as Int (0/1) not Bool
        let confirmedRaw = dict["confirmed"]
        let confirmed: Bool
        if let boolVal = confirmedRaw as? Bool {
            confirmed = boolVal
        } else if let intVal = confirmedRaw as? Int {
            confirmed = intVal != 0
        } else {
            confirmed = false
        }
        let blockHeight = dict["kernel_lookup_min_height"] as? Int

        // num_confirmations: approximate from node height.
        // kernel_lookup_min_height is the height at tx creation, not the mined block,
        // so this is an approximation (typically within 1 block).
        let confirmations: Int
        if confirmed, let bh = blockHeight, bh > 0, nodeHeight >= UInt64(bh) {
            confirmations = Int(nodeHeight - UInt64(bh))
        } else if confirmed {
            confirmations = 1
        } else {
            confirmations = 0
        }
        let kernelExcess = dict["kernel_excess"] as? String
        let slateId = dict["tx_slate_id"] as? String

        let status: TransactionStatus
        if confirmed {
            status = .confirmed
        } else {
            // Will be resolved to .confirming, .incomplete, or .confirmed after kernel verification
            status = .confirming
        }

        let creationTs = dict["creation_ts"] as? String ?? ""
        let date = Self.parseDate(creationTs) ?? Date()
        let fee = nanoToGrin(UInt64(dict["fee"] as? String ?? "0") ?? 0)

        let isInvoiceTx = slateId.map { SlatepackStore.shared.isInvoice(slateId: $0) } ?? false

        return Transaction(
            numericId: idNum,
            direction: direction,
            amount: amount,
            date: date,
            status: status,
            confirmations: confirmations,
            blockHeight: blockHeight,
            fee: fee,
            txId: "\(idNum)",
            kernelExcess: kernelExcess,
            slateId: slateId,
            txType: typeStr,
            isInvoice: isInvoiceTx
        )
    }
}
