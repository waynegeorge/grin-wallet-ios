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
//  QRScannerView.swift
//  grin-ios
//

import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasCompleted = false

    // Multi-part state
    private var expectedTotal = 0
    private var receivedParts: [Int: String] = [:]

    // UI elements for progress
    private var progressLabel: UILabel?
    private var progressBar: UIProgressView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showFallback()
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showFallback()
            return
        }

        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        // Scanning frame overlay
        let overlayView = UIView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.layer.borderColor = UIColor.white.cgColor
        overlayView.layer.borderWidth = 2
        overlayView.layer.cornerRadius = 12
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlayView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            overlayView.widthAnchor.constraint(equalToConstant: 250),
            overlayView.heightAnchor.constraint(equalToConstant: 250)
        ])

        // Instruction label
        let label = UILabel()
        label.text = "Scan QR Code"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: overlayView.topAnchor, constant: -20)
        ])

        // Progress label (hidden until multi-part detected)
        let pLabel = UILabel()
        pLabel.text = ""
        pLabel.textColor = .white
        pLabel.font = .systemFont(ofSize: 14, weight: .medium)
        pLabel.textAlignment = .center
        pLabel.translatesAutoresizingMaskIntoConstraints = false
        pLabel.isHidden = true
        view.addSubview(pLabel)
        NSLayoutConstraint.activate([
            pLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pLabel.topAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: 20)
        ])
        self.progressLabel = pLabel

        // Progress bar (hidden until multi-part detected)
        let pBar = UIProgressView(progressViewStyle: .default)
        pBar.translatesAutoresizingMaskIntoConstraints = false
        pBar.progressTintColor = UIColor(red: 1.0, green: 0.76, blue: 0.03, alpha: 1.0)
        pBar.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        pBar.isHidden = true
        view.addSubview(pBar)
        NSLayoutConstraint.activate([
            pBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pBar.topAnchor.constraint(equalTo: pLabel.bottomAnchor, constant: 8),
            pBar.widthAnchor.constraint(equalToConstant: 200)
        ])
        self.progressBar = pBar

        // Close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Cancel", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20)
        ])

        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func showFallback() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Multi-part parsing

    /// Parses a "grin:N/T:data" frame. Returns (partIndex, total, chunkData) or nil for single QR.
    private func parseMultipartFrame(_ value: String) -> (Int, Int, String)? {
        guard value.hasPrefix("grin:") else { return nil }
        let rest = String(value.dropFirst(5)) // drop "grin:"
        guard let slashIndex = rest.firstIndex(of: "/") else { return nil }
        let partStr = String(rest[rest.startIndex..<slashIndex])
        let afterSlash = String(rest[rest.index(after: slashIndex)...])
        guard let colonIndex = afterSlash.firstIndex(of: ":") else { return nil }
        let totalStr = String(afterSlash[afterSlash.startIndex..<colonIndex])
        let chunk = String(afterSlash[afterSlash.index(after: colonIndex)...])
        guard let part = Int(partStr), let total = Int(totalStr),
              part >= 1, part <= total, total > 0 else { return nil }
        return (part, total, chunk)
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasCompleted,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }

        // Try to parse as multi-part frame
        if let (part, total, chunk) = parseMultipartFrame(value) {
            expectedTotal = total
            receivedParts[part] = chunk

            // Update progress UI
            progressLabel?.isHidden = false
            progressBar?.isHidden = false
            progressLabel?.text = "Capturing: \(receivedParts.count) of \(total) parts"
            progressBar?.setProgress(Float(receivedParts.count) / Float(total), animated: true)

            // Haptic for each new part
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

            // Check if all parts received
            if receivedParts.count == total {
                hasCompleted = true
                captureSession?.stopRunning()

                // Reassemble in order
                var assembled = ""
                for i in 1...total {
                    assembled += receivedParts[i] ?? ""
                }

                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)

                onScan?(assembled)
            }
        } else {
            // Single QR code — original behavior
            hasCompleted = true
            captureSession?.stopRunning()

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            onScan?(value)
        }
    }
}
