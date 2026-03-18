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
//  AmountDial.swift
//  grin-ios
//

import SwiftUI

struct AmountDial: View {
    @Binding var amount: Double
    let maxAmount: Double

    @State private var lastAngle: CGFloat? = nil

    private let scale: CGFloat = 180
    private let indicatorLength: CGFloat = 15
    private let minAmount: CGFloat = 0
    private let stepSize: CGFloat = 0.0001

    private var innerScale: CGFloat {
        scale - indicatorLength
    }

    private var maxVal: CGFloat {
        CGFloat(maxAmount)
    }

    private var value: CGFloat {
        guard maxVal > minAmount else { return 0 }
        return CGFloat(amount - Double(minAmount)) / CGFloat(maxVal - minAmount)
    }

    private func angleDegrees(at point: CGPoint, center: CGPoint) -> CGFloat {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var degrees = 90 + atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    var body: some View {
        ZStack(alignment: .center) {
            // Inner draggable circle
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: innerScale, height: innerScale)

            // Outer tick ring (background)
            Circle()
                .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: indicatorLength, lineCap: .butt, lineJoin: .miter, dash: [3]))
                .frame(width: scale, height: scale)

            // Filled arc showing current value
            Circle()
                .trim(from: 0.0, to: value)
                .stroke(.white, style: StrokeStyle(lineWidth: indicatorLength, lineCap: .butt, lineJoin: .miter, dash: [3]))
                .rotationEffect(.degrees(-90))
                .frame(width: scale, height: scale)
        }
        .frame(width: scale + 10, height: scale + 10)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { dragValue in
                    let center = CGPoint(x: (scale + 10) / 2, y: (scale + 10) / 2)
                    let currentAngle = angleDegrees(at: dragValue.location, center: center)

                    guard let previous = lastAngle else {
                        lastAngle = currentAngle
                        return
                    }

                    // Calculate angular delta
                    var delta = currentAngle - previous
                    // Normalise to -180...180 to handle wraparound
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }

                    // Convert delta to amount change
                    let amountDelta = Double(delta / 360) * Double(maxVal - minAmount)
                    let newAmount = amount + amountDelta

                    // Clamp — don't wrap around
                    amount = min(max(newAmount, 0), Double(maxAmount))
                    lastAngle = currentAngle
                }
                .onEnded { _ in
                    lastAngle = nil
                }
        )
    }
}

#Preview {
    AmountDial(amount: .constant(1.5), maxAmount: 10.0)
        .frame(height: 200)
        .background(.black)
        .preferredColorScheme(.dark)
}
