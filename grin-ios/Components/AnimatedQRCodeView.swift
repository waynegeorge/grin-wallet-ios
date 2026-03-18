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
//  AnimatedQRCodeView.swift
//  grin-ios
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct AnimatedQRCodeView: View {
    let data: String
    var maxChunkSize: Int = 250
    var framesPerSecond: Double = 4

    @State private var currentFrame = 0
    @State private var timer: Timer?

    private var frames: [String] {
        let chars = Array(data)
        let total = max(1, Int(ceil(Double(chars.count) / Double(maxChunkSize))))

        if total == 1 {
            return [data]
        }

        var result: [String] = []
        for i in 0..<total {
            let start = i * maxChunkSize
            let end = min(start + maxChunkSize, chars.count)
            let chunk = String(chars[start..<end])
            result.append("grin:\(i + 1)/\(total):\(chunk)")
        }
        return result
    }

    private var isAnimated: Bool { frames.count > 1 }

    private func qrImage(for string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: qrImage(for: frames[currentFrame]))
                .interpolation(.none)
                .resizable()
                .scaledToFit()

            if isAnimated {
                HStack(spacing: 4) {
                    ForEach(0..<frames.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentFrame ? Color(red: 1.0, green: 0.76, blue: 0.03) : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 4)

                Text("Part \(currentFrame + 1) of \(frames.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: data) {
            currentFrame = 0
            stopTimer()
            startTimer()
        }
    }

    private func startTimer() {
        guard isAnimated else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / framesPerSecond, repeats: true) { _ in
            currentFrame = (currentFrame + 1) % frames.count
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    AnimatedQRCodeView(data: String(repeating: "BEGINSLATEPACK. abcdefghijklmnop. ENDSLATEPACK. ", count: 20))
        .frame(width: 220, height: 260)
        .padding()
        .background(.black)
}
