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
//  ReceiveView.swift
//  grin-ios
//

import SwiftUI

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    let walletService: WalletService
    let settings: AppSettings
    var nearbyService: NearbyService? = nil

    @State private var inputSlatepack: String = ""
    @State private var responseSlatepack: Slatepack?
    @State private var step: ReceiveStep = .pasteSlatepack
    @State private var showQRScanner = false

    // Invoice mode state
    @State private var invoiceAmount: Double = 0.0
    @State private var invoiceSlatepack: Slatepack?
    @State private var invoiceResponseInput: String = ""
    @State private var invoiceError: String?
    @State private var isEditingAmount: Bool = false
    @State private var manualEntry: String = ""
    @FocusState private var amountFieldFocused: Bool

    // Nearby invoice state
    @State private var showNearbyInvoice = false
    @State private var selectedPeer: NearbyPeer?
    @State private var nearbyInvoiceStatus: String = ""

    enum ReceiveStep {
        // SRS mode (existing)
        case pasteSlatepack
        case shareResponse

        // RSR mode (new)
        case invoiceEnterAmount
        case invoiceShare
        case invoicePasteResponse
        case invoiceFinalized
    }

    private var isSRSMode: Bool {
        step == .pasteSlatepack || step == .shareResponse
    }

    private var isInvoiceMode: Bool {
        !isSRSMode
    }

    private var stepCount: Int {
        isInvoiceMode ? 4 : 2
    }

    private var stepIndex: Int {
        switch step {
        case .pasteSlatepack: return 0
        case .shareResponse: return 1
        case .invoiceEnterAmount: return 0
        case .invoiceShare: return 1
        case .invoicePasteResponse: return 2
        case .invoiceFinalized: return 3
        }
    }

    private var amountFormat: String {
        "%.\(settings.grinDecimalPlaces)f"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Step indicator
                HStack(spacing: 8) {
                    ForEach(0..<stepCount, id: \.self) { i in
                        Capsule()
                            .fill(i <= stepIndex ? .white : .white.opacity(0.15))
                            .frame(height: 3)
                    }
                }

                switch step {
                case .pasteSlatepack:
                    pasteView
                case .shareResponse:
                    responseView
                case .invoiceEnterAmount:
                    invoiceEnterAmountView
                case .invoiceShare:
                    invoiceShareView
                case .invoicePasteResponse:
                    invoicePasteResponseView
                case .invoiceFinalized:
                    invoiceFinalizedView
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                walletService.invoiceInProgress = false
                nearbyService?.isInvoiceFlowActive = false
                nearbyService?.resetSendingStatus()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .invoiceFinalized {
                        Button("Done") { dismiss() }
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { scannedText in
                    inputSlatepack = scannedText
                    showQRScanner = false
                }
            }
        }
    }

    // MARK: - Paste Slatepack

    private var pasteView: some View {
        VStack(spacing: 20) {
            Text("Paste Sender's Slatepack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Paste the slatepack from the sender. You will sign it and return a response.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            TextEditor(text: $inputSlatepack)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

            HStack(spacing: 12) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        inputSlatepack = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    showQRScanner = true
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    Task {
                        responseSlatepack = await walletService.receiveSlatepack(inputSlatepack)
                        if responseSlatepack != nil {
                            withAnimation { step = .shareResponse }
                        }
                    }
                } label: {
                    Text("Sign")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(inputSlatepack.isEmpty)
            }

            Button {
                withAnimation { step = .invoiceEnterAmount }
            } label: {
                Text("Receive via Invoice instead?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Share Response

    private var responseView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Slatepack Signed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Send this response back to the sender to complete the transaction.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let slatepack = responseSlatepack {
                SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

                AnimatedQRCodeView(data: slatepack.fullString)
                    .frame(width: 220, height: 260)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                    )

                Text("Show this QR code to the sender")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                ShareLink(item: slatepack.fullString) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Invoice: Enter Amount

    private var invoiceEnterAmountView: some View {
        VStack(spacing: 16) {
            Text("Request Payment")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Enter the amount you want to receive. An invoice slatepack will be generated for the sender.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Amount display
            VStack(spacing: 4) {
                ZStack {
                    TextField("", text: $manualEntry)
                        .keyboardType(.decimalPad)
                        .focused($amountFieldFocused)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    if let val = Double(manualEntry) {
                                        invoiceAmount = max(val, 0)
                                    }
                                    isEditingAmount = false
                                    amountFieldFocused = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                        .onChange(of: amountFieldFocused) { _, focused in
                            if !focused, let val = Double(manualEntry) {
                                invoiceAmount = max(val, 0)
                                isEditingAmount = false
                            }
                        }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if isEditingAmount {
                            Text(manualEntry.isEmpty ? "0" : manualEntry)
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                        } else {
                            Text(String(format: amountFormat, invoiceAmount))
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                        Text("ツ")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        manualEntry = invoiceAmount > 0 ? String(format: amountFormat, invoiceAmount) : ""
                        isEditingAmount = true
                        amountFieldFocused = true
                    }
                }
            }

            AmountDial(amount: $invoiceAmount, maxAmount: 1000)
                .frame(width: 200, height: 200)

            if let error = invoiceError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    invoiceError = nil
                    nearbyService?.isInvoiceFlowActive = true
                    invoiceSlatepack = await walletService.issueInvoice(amount: invoiceAmount)
                    if invoiceSlatepack != nil {
                        withAnimation { step = .invoiceShare }
                    } else {
                        invoiceError = walletService.errorMessage ?? "Failed to create invoice"
                    }
                }
            } label: {
                Text("Generate Invoice")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(invoiceAmount <= 0)

            Button {
                withAnimation { step = .pasteSlatepack }
            } label: {
                Text("Sign a slatepack instead?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Invoice: Share

    private var invoiceShareView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.03))

            Text("Invoice Created")
                .font(.system(size: 18, weight: .semibold))

            Text("Share this invoice with the sender. They will process it and return a response.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let slatepack = invoiceSlatepack {
                SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

                QRCodeView(data: slatepack.fullString)
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))

                ShareLink(item: slatepack.fullString) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            if let nearbyService, settings.nearbyEnabled {
                nearbyInvoiceSection
            }

            Button {
                withAnimation { step = .invoicePasteResponse }
            } label: {
                Text("I Have the Response")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Nearby Invoice Send

    @ViewBuilder
    private var nearbyInvoiceSection: some View {
        VStack(spacing: 12) {
            Button {
                showNearbyInvoice.toggle()
                if showNearbyInvoice {
                    nearbyService?.startSearching()
                } else {
                    nearbyService?.stopSearching()
                }
            } label: {
                Label("Send to Nearby Device", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            if showNearbyInvoice {
                nearbyInvoicePeerList
            }
        }
    }

    private var nearbyInvoicePeerList: some View {
        VStack(spacing: 0) {
            if let nearbyService, nearbyService.isSearching && nearbyService.peers.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Searching…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }

            if let nearbyService {
                ForEach(nearbyService.peers) { peer in
                    nearbyInvoicePeerButton(for: peer)

                    if peer.id != nearbyService.peers.last?.id {
                        Divider().overlay(.white.opacity(0.06))
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func nearbyInvoicePeerButton(for peer: NearbyPeer) -> some View {
        HStack {
            Image(systemName: peer.status == .connected ? "iphone.radiowaves.left.and.right" : "iphone")
                .foregroundStyle(peer.status == .connected ? .green : .secondary)
            Text(peer.displayName)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            if selectedPeer?.id == peer.id {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView()
                        .tint(.primary)
                    Text(nearbyInvoiceStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else if peer.status == .connecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.secondary)
                        .controlSize(.small)
                    Text("Connecting…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    selectedPeer = peer
                    nearbyInvoiceStatus = "Sending invoice…"
                    Task { await sendInvoiceViaNearby(to: peer) }
                } label: {
                    Text("Send")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.76, blue: 0.03))
                .foregroundStyle(.black)
                .disabled(selectedPeer != nil)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private func sendInvoiceViaNearby(to peer: NearbyPeer) async {
        guard let nearbyService, let slatepack = invoiceSlatepack else {
            nearbyInvoiceStatus = "No invoice to send"
            return
        }

        nearbyService.isInvoiceFlowActive = true

        nearbyInvoiceStatus = "Sending to \(peer.displayName)…"
        await nearbyService.sendInvoice(slatepack.fullString, amount: invoiceAmount, to: peer)

        nearbyInvoiceStatus = "Waiting for \(peer.displayName) to approve…"

        // Wait for the response slatepack
        var attempts = 0
        while nearbyService.receivedSlatepack == nil && attempts < 120 {
            try? await Task.sleep(for: .seconds(1))
            attempts += 1
        }

        if nearbyService.receivedSlatepack != nil {
            nearbyInvoiceStatus = "Response received — finalising…"
            let responseRaw = nearbyService.receivedRawSlatepack ?? nearbyService.receivedSlatepack!.fullString
            nearbyService.receivedSlatepack = nil
            nearbyService.receivedRawSlatepack = nil

            let success = await walletService.finalizeInvoice(responseRaw)
            if success {
                nearbyService.isInvoiceFlowActive = false
                withAnimation { step = .invoiceFinalized }
            } else {
                nearbyInvoiceStatus = "Finalisation failed"
                nearbyService.isInvoiceFlowActive = false
            }
        } else {
            nearbyInvoiceStatus = "Timed out waiting for response"
            nearbyService.isInvoiceFlowActive = false
        }
    }

    // MARK: - Invoice: Paste Response

    private var invoicePasteResponseView: some View {
        VStack(spacing: 20) {
            Text("Paste Sender's Response")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Paste the response slatepack from the sender to finalise the invoice.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            TextEditor(text: $invoiceResponseInput)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

            HStack(spacing: 12) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        invoiceResponseInput = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    Task {
                        invoiceError = nil
                        let success = await walletService.finalizeInvoice(invoiceResponseInput)
                        if success {
                            withAnimation { step = .invoiceFinalized }
                        } else {
                            invoiceError = walletService.errorMessage ?? "Finalisation failed"
                        }
                    }
                } label: {
                    if walletService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Finalise")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(invoiceResponseInput.isEmpty || walletService.isLoading)
            }

            if let error = invoiceError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Invoice: Finalized

    private var invoiceFinalizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Payment Received")
                .font(.system(size: 20, weight: .semibold))

            Text("\(String(format: amountFormat, invoiceAmount)) ツ")
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            Text("The invoice has been finalised and broadcast to the network.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
    }
}

#Preview {
    ReceiveView(walletService: WalletService(settings: AppSettings()), settings: AppSettings())
        .preferredColorScheme(.dark)
}
