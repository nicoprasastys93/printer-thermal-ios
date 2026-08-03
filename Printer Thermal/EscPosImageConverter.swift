//
//  EscPosImageConverter.swift
//  Printer Thermal
//
//  Created by NPSK Macbook on 30/07/26.
//

import UIKit
import Accelerate
import CoreGraphics

class EscPosImageConverter {
    /// Mengonversi UIImage menjadi Data (byte array) format ESC/POS `GS v 0`
    /// - Parameters:
    ///   - image: Gambar yang akan dikonversi
    ///   - maxWidth: Lebar maksimal gambar dalam pixel (standar printer 58mm = 384px, 80mm = 576px)
    /// - Returns: Data ESC/POS yang siap dikirim via Bluetooth/TCP/USB ke printer
    static func convertToEscPosData(_ image: UIImage, maxWidth: Int = 384, completion: @escaping((_ data: Data?)-> Void)) {
        DispatchQueue.global(qos: .utility).async{
            let timeStart = CFAbsoluteTimeGetCurrent()
            // 1. Resize gambar agar sesuai dengan lebar kertas printer (harus kelipatan 8)
            let targetWidth = (maxWidth / 8) * 8
            guard targetWidth > 0 else {
                completion(nil)
                return
            }
            
            guard let resizedCGImage = image.cgImage else {
                completion(nil)
                return
            }
            
            let width = resizedCGImage.width
            let height = resizedCGImage.height
            
            // 2. Ambil data pixel RGBA dari CGImage
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            var rawPixels = [UInt8](repeating: 0, count: height * bytesPerRow)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: &rawPixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                completion(nil)
                return
            }

            context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // 2. Konversi RGBA -> Grayscale pakai vImage (menggantikan loop luminance manual)
            var grayPixels = [UInt8](repeating: 0, count: width * height)
            var vImageError = kvImageNoError
            
            rawPixels.withUnsafeMutableBytes { rawRawBufferPtr in
                grayPixels.withUnsafeMutableBytes { grayRawBufferPtr in
                    var sourceBuffer = vImage_Buffer(
                        data: rawRawBufferPtr.baseAddress,
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: bytesPerRow
                    )

                    var destBuffer = vImage_Buffer(
                        data: grayRawBufferPtr.baseAddress,
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width
                    )

                    let divisor: Int32 = 256
                    let coefficients: [Int16] = [77, 151, 28, 0] // R, G, B, Alpha(diabaikan)

                    vImageError = vImageMatrixMultiply_ARGB8888ToPlanar8(
                        &sourceBuffer,
                        &destBuffer,
                        coefficients,
                        divisor,
                        nil,
                        0,
                        vImage_Flags(kvImageNoFlags)
                    )
                }
            }

            guard vImageError == kvImageNoError else {
                completion(nil)
                return
            }

            // 3. Konversi grayscale ke Bitwise Raster (1-bit per pixel)
            var bitmapBytes = [UInt8]()
            let bytesPerRasterRow = (width + 7) / 8

            for y in 0..<height {
                for byteIdx in 0..<bytesPerRasterRow {
                    var byteAccumulator: UInt8 = 0

                    for bitIdx in 0..<8 {
                        let x = byteIdx * 8 + bitIdx
                        let grayOffset = (y * width) + x
                        let luminance = grayPixels[grayOffset]

                        // Threshold sederhana (128)
                        if luminance < 128 {
                            byteAccumulator |= (0x80 >> bitIdx)
                        }
                    }
                    bitmapBytes.append(byteAccumulator)
                }
            }
            
            // 4. Buat Perintah Header ESC/POS `GS v 0 m xL xH yL yH`
            var escPosData = Data()
            
            // Reset/Init Printer (ESC @)
            escPosData.append(contentsOf: [0x1B, 0x40])
            
            // Perintah GS v 0
            let m: UInt8 = 0 // Mode: Normal
            let xL = UInt8(bytesPerRasterRow % 256)
            let xH = UInt8(bytesPerRasterRow / 256)
            let yL = UInt8(height % 256)
            let yH = UInt8(height / 256)
            
            let header: [UInt8] = [0x1D, 0x76, 0x30, m, xL, xH, yL, yH]
            escPosData.append(contentsOf: header)
            
            // Tambahkan data raster bitmap
            escPosData.append(contentsOf: bitmapBytes)
            // line feed
            escPosData.append(contentsOf: [0x0A])
            escPosData.append(contentsOf: [0x0A])
            // cut
            escPosData.append(contentsOf: [0x1D, 0x56, 0x00])
            
            let timeEnd = CFAbsoluteTimeGetCurrent()
            let timeResult = timeEnd - timeStart
            print("========PROSES IMAGE TO ESP/POS========")
            print("Background Process")
            print("Data count => \(escPosData.count)")
            print("Finish Add => \(timeResult) detik")
            completion(escPosData)
        }
    }
}
