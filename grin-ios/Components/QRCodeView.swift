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
//  QRCodeView.swift
//  grin-ios
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let data: String

    private var qrImage: UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(data.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        // Scale up for sharpness
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        Image(uiImage: qrImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
    }
}

#Preview {
    QRCodeView(data: "BEGINSLATEPACK. test data here. ENDSLATEPACK.")
        .frame(width: 200, height: 200)
        .padding()
        .background(.black)
}
