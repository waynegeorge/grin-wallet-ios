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
//  ResumeTransactionView.swift
//  grin-ios
//
//  Resume an incomplete transaction by re-sharing or finalizing the stored slatepack.
//

import SwiftUI

struct ResumeTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction
    let walletService: WalletService
    let settings: AppSettings

    @State private var responseSlatepack: String = ""
    @State private var errorMessage: String?
    @State private var finalized = false
    @State private var showQRCode = false
    @State private var qrVisible = false
    @State private var showQRScanner = false

    private var storedSlatepack: String? {
        if transaction.isInvoice {
            if transaction.direction == .received {
                return SlatepackStore.shared.get(txId: transaction.numericId, type: .invoice)
            } else {
                return SlatepackStore.shared.get(txId: transaction.numericId, type: .invoiceResponse)
            }
        } else {
            if transaction.direction == .sent {
                return SlatepackStore.shared.get(txId: transaction.numericId, type: .initial)
            } else {
                return SlatepackStore.shared.get(txId: transaction.numericId, type: .response)
            }
        }
    }

    private var amountFormat: String {
        "%.\(settings.grinDecimalPlaces)f"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if finalized {
                    finalizedView
                } else if transaction.isInvoice && transaction.direction == .received {
                    // RSR invoicer: re-share invoice, paste response, finalize
                    resumeInvoiceReceiverView
                } else if transaction.isInvoice && transaction.direction == .sent {
                    // RSR payer: re-share processed response
                    resumeInvoiceSenderView
                } else if transaction.direction == .sent {
                    resumeSentView
                } else {
                    resumeReceivedView
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Resume Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finalized ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .onDisappear {
                if !finalized {
                    walletService.sendInProgress = false
                    walletService.invoiceInProgress = false
                }
            }
        }
    }

    // MARK: - Resume Sent (re-share initial slatepack + paste response to finalize)

    private var resumeSentView: some View {
        VStack(spacing: 20) {
            // Transaction summary
            transactionSummary

            if let slatepackStr = storedSlatepack,
               let slatepack = SlatepackService.shared.parseSync(slatepackStr) {
                Text("Share This Slatepack")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text("Re-share this with the recipient so they can sign it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                if showQRCode {
                    QRCodeView(data: slatepack.fullString)
                        .frame(width: 200, height: 200)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                        .opacity(qrVisible ? 1 : 0)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeIn(duration: 0.25)) { qrVisible = true }
                            }
                        }
                } else {
                    SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

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
                    qrVisible = false
                    showQRCode.toggle()
                } label: {
                    Label(showQRCode ? "Show Slatepack" : "Show as QR Code",
                          systemImage: showQRCode ? "doc.plaintext" : "qrcode")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            Divider().overlay(.white.opacity(0.1))

            // Paste response section
            Text("Paste Response to Finalize")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            TextEditor(text: $responseSlatepack)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 100)
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
                        responseSlatepack = pasted
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
                .sheet(isPresented: $showQRScanner) {
                    QRScannerView { scannedText in
                        responseSlatepack = scannedText
                        showQRScanner = false
                    }
                }

                Button {
                    Task { await doFinalize(responseSlatepack) }
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
                .disabled(responseSlatepack.isEmpty || walletService.isLoading)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Resume Received (re-share response slatepack)

    private var resumeReceivedView: some View {
        VStack(spacing: 20) {
            transactionSummary

            Image(systemName: "arrow.uturn.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Share Response Slatepack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Send this response back to the sender so they can finalize the transaction.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let slatepackStr = storedSlatepack,
               let slatepack = SlatepackService.shared.parseSync(slatepackStr) {
                SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

                AnimatedQRCodeView(data: slatepack.fullString)
                    .frame(width: 220, height: 260)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))

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
        }
    }

    // MARK: - Finalized

    private var finalizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Transaction Sent")
                .font(.system(size: 20, weight: .semibold))

            Text("\(String(format: amountFormat, transaction.amount)) ツ")
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            Text("The transaction has been finalised and broadcast to the network.")
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

    // MARK: - Helpers

    private var transactionSummary: some View {
        HStack {
            Image(systemName: transaction.direction == .received ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(transaction.direction == .received ? .green : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.directionLabel)
                    .font(.system(size: 15, weight: .semibold))
                Text("Incomplete")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Text("\(String(format: amountFormat, transaction.amount)) ツ")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func doFinalize(_ slatepackString: String) async {
        errorMessage = nil
        let success: Bool
        if transaction.isInvoice {
            walletService.invoiceInProgress = true
            success = await walletService.finalizeInvoice(slatepackString)
        } else {
            walletService.sendInProgress = true
            success = await walletService.finalizeTransaction(slatepackString)
        }
        if success {
            SlatepackStore.shared.remove(txId: transaction.numericId)
            withAnimation { finalized = true }
        } else {
            errorMessage = walletService.errorMessage ?? "Finalisation failed"
        }
    }

    // MARK: - Resume Invoice Receiver (re-share invoice + paste response to finalize)

    private var resumeInvoiceReceiverView: some View {
        VStack(spacing: 20) {
            transactionSummary

            if let slatepackStr = storedSlatepack,
               let slatepack = SlatepackService.shared.parseSync(slatepackStr) {
                Text("Share This Invoice")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text("Re-share this invoice with the sender so they can process it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

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

            Divider().overlay(.white.opacity(0.1))

            Text("Paste Response to Finalize")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            TextEditor(text: $responseSlatepack)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 100)
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
                        responseSlatepack = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    Task { await doFinalize(responseSlatepack) }
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
                .disabled(responseSlatepack.isEmpty || walletService.isLoading)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Resume Invoice Sender (re-share processed response)

    private var resumeInvoiceSenderView: some View {
        VStack(spacing: 20) {
            transactionSummary

            Image(systemName: "arrow.uturn.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Share Response Slatepack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Send this response back to the invoicer so they can finalise the transaction.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let slatepackStr = storedSlatepack,
               let slatepack = SlatepackService.shared.parseSync(slatepackStr) {
                SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

                AnimatedQRCodeView(data: slatepack.fullString)
                    .frame(width: 220, height: 260)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))

                Text("Show this QR code to the invoicer")
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
        }
    }
}
