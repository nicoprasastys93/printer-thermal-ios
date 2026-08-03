//
//  ViewController.swift
//  Printer Thermal
//
//  Created by NPSK Macbook on 29/07/26.
//

import UIKit
import CoreBluetooth
import PDFKit
import Accelerate
import Vision

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    @IBOutlet weak var bottomSheetView: UIView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var printButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    private var centralManager: CBCentralManager!
    private var printerPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    var isConnected = false
    var discoveredPrinters: [CBPeripheral] = []
    private var pendingChunks: [Data] = []
    private var isSending = false
    private var chunkIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        bottomSheetView.backgroundColor = .white
        bottomSheetView.layer.cornerRadius = 24
        bottomSheetView.layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner
        ]

        bottomSheetView.layer.masksToBounds = false
        bottomSheetView.layer.shadowColor = UIColor.black.cgColor
        bottomSheetView.layer.shadowOpacity = 0.15
        bottomSheetView.layer.shadowOffset = CGSize(width: 0, height: -2)
        bottomSheetView.layer.shadowRadius = 12
        
        tableView.dataSource = self
        tableView.delegate = self
        
        printButton.setTitle("Print", for: .normal)
        printButton.addTarget(self, action: #selector(actionPrint), for: .touchUpInside)
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            tryAutoReconnect()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let displayName = peripheral.name ?? localName
        if let displayName = displayName, displayName != "", !discoveredPrinters.contains(where: {$0.name == displayName}){
            discoveredPrinters.append(peripheral)
            tableView.reloadData()
        }
    }

    // MARK: - Connect
    func connect(to peripheral: CBPeripheral) {
        printerPeripheral = peripheral
        printerPeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        savePrinterIdentifier(peripheral)
        peripheral.discoverServices(nil)
    }

    // MARK: - Discover services & characteristics
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics(nil, for: $0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        service.characteristics?.forEach { characteristic in
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
        }
    }

    // MARK: - Print
    func printPOS() {
        let base64String = "JVBERi0xLjcKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZwovT3V0bGluZXMgMiAwIFIKL1BhZ2VzIDMgMCBSID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9PdXRsaW5lcyAvQ291bnQgMCA+PgplbmRvYmoKMyAwIG9iago8PCAvVHlwZSAvUGFnZXMKL0tpZHMgWzYgMCBSCl0KL0NvdW50IDEKL1Jlc291cmNlcyA8PAovUHJvY1NldCA0IDAgUgovRm9udCA8PCAKL0YxIDggMCBSCi9GMiA5IDAgUgo+Pgo+PgovTWVkaWFCb3ggWzAuMDAwIDAuMDAwIDIzMC4wMDAgMTAwMC4wMDBdCiA+PgplbmRvYmoKNCAwIG9iagpbL1BERiAvVGV4dCBdCmVuZG9iago1IDAgb2JqCjw8Ci9Qcm9kdWNlciAo/v8AZABvAG0AcABkAGYAIAAzAC4AMQAuADAAIAArACAAQwBQAEQARikKL0NyZWF0aW9uRGF0ZSAoRDoyMDI2MDgwMzEzMzI1NiswNycwMCcpCi9Nb2REYXRlIChEOjIwMjYwODAzMTMzMjU2KzA3JzAwJykKL1RpdGxlICj+/wBCAGkAbABsKQo+PgplbmRvYmoKNiAwIG9iago8PCAvVHlwZSAvUGFnZQovTWVkaWFCb3ggWzAuMDAwIDAuMDAwIDIzMC4wMDAgMTAwMC4wMDBdCi9QYXJlbnQgMyAwIFIKL0NvbnRlbnRzIDcgMCBSCj4+CmVuZG9iago3IDAgb2JqCjw8IC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCi9MZW5ndGggMjc2ID4+CnN0cmVhbQp4nI2QO08DQQyE+/yKKaGIsb27d7vpLi9ICJyUrEQRpUAK0EATkMjPx3mALuSQaFzY/mbs6TAxM5p189LpZwSmQhjJOyo1Iq9xNRYIU0B+BpYX1XA4yZP6vpphcDMa3I7mlyvkKUZ5j5ekziOxJ1U54Ar1xEf8oQ9JqNCEdmM7IMZAwq7FU1mLLseuDUV7WvZCbPLilIK5/i1wVw8XP8T56/Nra5YBn2BMsYSSik9lEFPzUbCy/rqj5rI/0yIqPN7MV4j3vofOKxZnOi4VpXjnJDh31PmNmVAKlOKpUCOXQshxaHlLtifZKxVmsltn15bCoJ5VGM/qKrel7wN5u+G/Lrauoi3rT9uPzeM75Bv6ArjJhAIKZW5kc3RyZWFtCmVuZG9iago4IDAgb2JqCjw8IC9UeXBlIC9Gb250Ci9TdWJ0eXBlIC9UeXBlMQovTmFtZSAvRjEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKL0VuY29kaW5nIC9XaW5BbnNpRW5jb2RpbmcKPj4KZW5kb2JqCjkgMCBvYmoKPDwgL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9OYW1lIC9GMgovQmFzZUZvbnQgL0hlbHZldGljYS1Cb2xkCi9FbmNvZGluZyAvV2luQW5zaUVuY29kaW5nCj4+CmVuZG9iagp4cmVmCjAgMTAKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNzQgMDAwMDAgbiAKMDAwMDAwMDEyMCAwMDAwMCBuIAowMDAwMDAwMjg1IDAwMDAwIG4gCjAwMDAwMDAzMTQgMDAwMDAgbiAKMDAwMDAwMDQ4MyAwMDAwMCBuIAowMDAwMDAwNTg3IDAwMDAwIG4gCjAwMDAwMDA5MzUgMDAwMDAgbiAKMDAwMDAwMTA0MiAwMDAwMCBuIAp0cmFpbGVyCjw8Ci9TaXplIDEwCi9Sb290IDEgMCBSCi9JbmZvIDUgMCBSCi9JRFs8YWUzYmRjMTVmOWJlNzY5MmQ0NTgyM2JiYmFjOGFhYTM+PGFlM2JkYzE1ZjliZTc2OTJkNDU4MjNiYmJhYzhhYWEzPl0KPj4Kc3RhcnR4cmVmCjExNTQKJSVFT0YK"
        
//        let base64String = "JVBERi0xLjcKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZwovT3V0bGluZXMgMiAwIFIKL1BhZ2VzIDMgMCBSID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9PdXRsaW5lcyAvQ291bnQgMCA+PgplbmRvYmoKMyAwIG9iago8PCAvVHlwZSAvUGFnZXMKL0tpZHMgWzYgMCBSCl0KL0NvdW50IDEKL1Jlc291cmNlcyA8PAovUHJvY1NldCA0IDAgUgovRm9udCA8PCAKL0YxIDggMCBSCi9GMiA5IDAgUgo+Pgo+PgovTWVkaWFCb3ggWzAuMDAwIDAuMDAwIDIzMC4wMDAgMTAwMC4wMDBdCiA+PgplbmRvYmoKNCAwIG9iagpbL1BERiAvVGV4dCBdCmVuZG9iago1IDAgb2JqCjw8Ci9Qcm9kdWNlciAo/v8AZABvAG0AcABkAGYAIAAzAC4AMQAuADAAIAArACAAQwBQAEQARikKL0NyZWF0aW9uRGF0ZSAoRDoyMDI2MDczMTExNDYyMCswNycwMCcpCi9Nb2REYXRlIChEOjIwMjYwNzMxMTE0NjIwKzA3JzAwJykKL1RpdGxlICj+/wBCAGkAbABsKQo+PgplbmRvYmoKNiAwIG9iago8PCAvVHlwZSAvUGFnZQovTWVkaWFCb3ggWzAuMDAwIDAuMDAwIDIzMC4wMDAgMTAwMC4wMDBdCi9QYXJlbnQgMyAwIFIKL0NvbnRlbnRzIDcgMCBSCj4+CmVuZG9iago3IDAgb2JqCjw8IC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCi9MZW5ndGggMjQ1ID4+CnN0cmVhbQp4nH2QsU4DQQxE+/uKKaGIsb323m46Eg5QEEJKTkoRpUAK0EATkMjns7kEdIQTjYux34ztiomZ0a/bl2rSIgXy2pEtUK0J7QYX1wJhcrTPwOpsettM75r5+RrtDE27Z7wmDYbMRqpyYBRqxEdmOYFkXKIP7dslNSUn4TAQpKxxxPVIM8TGlsbCfV6CUWL9x+D+4WrxQ/y9d35TxHLqJxgzrKCkUTRGyyFycqyLvqlUybs1mUoLbyU3UOhyD8orFqc+EsXcstc5ZT36nGLFKDvlZL+Men+JUuZ94CzZ9d8QI5Wtu3EOQ1942n1sH98h39AXaj1qvQplbmRzdHJlYW0KZW5kb2JqCjggMCBvYmoKPDwgL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9OYW1lIC9GMQovQmFzZUZvbnQgL0hlbHZldGljYQovRW5jb2RpbmcgL1dpbkFuc2lFbmNvZGluZwo+PgplbmRvYmoKOSAwIG9iago8PCAvVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL05hbWUgL0YyCi9CYXNlRm9udCAvSGVsdmV0aWNhLUJvbGQKL0VuY29kaW5nIC9XaW5BbnNpRW5jb2RpbmcKPj4KZW5kb2JqCnhyZWYKMCAxMAowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA3NCAwMDAwMCBuIAowMDAwMDAwMTIwIDAwMDAwIG4gCjAwMDAwMDAyODUgMDAwMDAgbiAKMDAwMDAwMDMxNCAwMDAwMCBuIAowMDAwMDAwNDgzIDAwMDAwIG4gCjAwMDAwMDA1ODcgMDAwMDAgbiAKMDAwMDAwMDkwNCAwMDAwMCBuIAowMDAwMDAxMDExIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgMTAKL1Jvb3QgMSAwIFIKL0luZm8gNSAwIFIKL0lEWzw5NDg3ZTI5MzU2MzliMmE1MmY1YzBlY2U0MTA3NWIwNj48OTQ4N2UyOTM1NjM5YjJhNTJmNWMwZWNlNDEwNzViMDY+XQo+PgpzdGFydHhyZWYKMTEyMwolJUVPRgo="
//        if let decodedData = Data(base64Encoded: base64String) {
//            let pdf = PDFDocument(data: decodedData)
//            
//            guard let page = pdf?.page(at: 0) else {
//                return
//            }
//            
//            let image = page.thumbnail(
//                of: CGSize(width: 576, height: 1000),
//                for: .mediaBox
//            )
//            
//            imageView.image = image
//            
//            if let printData = EscPosImageConverter.convertToEscPosData(image, maxWidth: 576) {
//                print("Berhasil mengonversi gambar! Ukuran byte: \(printData.count) bytes")
//                let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ?
//                    .withoutResponse : .withResponse
//                
//                peripheral.writeValue(printData, for: characteristic, type: writeType)
//            }
//        }
        if let decodData = Data(base64Encoded: base64String){
            imageFromPDFData(decodData){ image in
                if let image = image{
                    DispatchQueue.main.async {
                        self.imageView.image = image
                    }
                    EscPosImageConverter.convertToEscPosData(image, maxWidth: 576) { data in
                        DispatchQueue.global(qos: .utility).async {
                            if let data = data{
//                                print("Berhasil mengonversi gambar! Ukuran byte: \(data.count) bytes")
//                                let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ?
//                                    .withoutResponse : .withResponse
//                                
//                                peripheral.writeValue(data, for: characteristic, type: writeType)
                                self.sendDataInChunks(data)
                            }
                        }
                    }
                }
            }
        }
    }
    func imageFromPDFData(_ data: Data, completion: @escaping((_ image: UIImage?)-> Void)){
        DispatchQueue.global(qos: .utility).async{
            let startTime = CFAbsoluteTimeGetCurrent()
            // 1. Buat provider data dan dokumen CGPDF
            guard let provider = CGDataProvider(data: data as CFData),
                  let pdfDocument = CGPDFDocument(provider),
                  let page = pdfDocument.page(at: 1)
            else {
                // Halaman CGPDF dimulai dari 1
                completion(nil)
                return
            }
            
            // 2. Ambil ukuran asli halaman PDF
            let pageRect = page.getBoxRect(.mediaBox)
            
            // 3. Setup graphics context dengan ukuran yang diinginkan
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                let context = ctx.cgContext
                
                context.setFillColor(UIColor.white.cgColor)
                context.fill(pageRect)
                
                // 4. Core Graphics menggunakan koordinat terbalik, kita perlu membalik orientasinya
                context.saveGState()
                context.translateBy(x: 0.0, y: pageRect.size.height)
                context.scaleBy(x: 1.0, y: -1.0)
                
                // 5. Gambar PDF ke dalam context
                context.drawPDFPage(page)
                context.restoreGState()
            }
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("Proses di background [\(Thread.current)] selesai dalam: \(timeElapsed) detik")
            
            
            let finalImage = self.cropToContentAccelerate(image: image, padding: 0)
            
            completion(finalImage)
        }
    }
    
//    func cropToContent(image: UIImage, padding: CGFloat, threshold: UInt8 = 245) -> UIImage? {
//        guard let cgImage = image.cgImage else { return nil }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        
//        guard let dataProvider = cgImage.dataProvider,
//              let data = dataProvider.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return image
//        }
//        
//        let bytesPerPixel = cgImage.bitsPerPixel / 8
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        var minX = width
//        var maxX = 0
//        var minY = height
//        var maxY = 0
//        var foundContent = false
//        
//        // Scan tiap pixel (bisa di-skip step > 1 kalau mau lebih cepat)
//        for y in 0..<height {
//            let rowStart = y * bytesPerRow
//            for x in 0..<width {
//                let pixelIndex = rowStart + x * bytesPerPixel
//                guard pixelIndex + 2 < CFDataGetLength(data) else { continue }
//                
//                let r = bytes[pixelIndex]
//                let g = bytes[pixelIndex + 1]
//                let b = bytes[pixelIndex + 2]
//                
//                // Kalau bukan putih -> ini konten
//                if r < threshold || g < threshold || b < threshold {
//                    foundContent = true
//                    if x < minX { minX = x }
//                    if x > maxX { maxX = x }
//                    if y < minY { minY = y }
//                    if y > maxY { maxY = y }
//                }
//            }
//        }
//        
//        guard foundContent else { return nil } // halaman benar-benar kosong
//        
//        // Tambah padding, tapi jangan sampai keluar batas image
//        let paddingPx = Int(padding * (image.scale > 0 ? 1 : 1)) // padding dalam pixel image
//        let cropX = max(0, minX - paddingPx)
//        let cropY = max(0, minY - paddingPx)
//        let cropWidth = min(width - cropX, (maxX - minX) + paddingPx * 2)
//        let cropHeight = min(height - cropY, (maxY - minY) + paddingPx * 2)
//        
//        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
//        
//        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }
//        
//        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
//    }

//    func cropToContentUsingVision(image: UIImage, padding: CGFloat = 10) -> UIImage? {
//        guard let cgImage = image.cgImage else { return nil }
//        
//        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
//        let request = VNRecognizeTextRequest()
//        request.recognitionLevel = .fast // atau .accurate jika butuh lebih teliti
//        
//        do {
//            try requestHandler.perform([request])
//            
//            guard let results = request.results, !results.isEmpty else { return nil }
//            
//            // Gabungkan seluruh bounding box dari teks yang terdeteksi
//            var boundingBox = results[0].boundingBox
//            for observation in results.dropFirst() {
//                boundingBox = boundingBox.union(observation.boundingBox)
//            }
//            
//            // Konversi normalized coordinates (0.0 - 1.0) ke koordinat pixel
//            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
//            
//            // Vision menggunakan origin di Kiri-Bawah, CGImage di Kiri-Atas
//            var cropRect = VNImageRectForNormalizedRect(boundingBox, Int(imageSize.width), Int(imageSize.height))
//            cropRect.origin.y = CGFloat(cgImage.height) - cropRect.maxY
//            
//            // Tambahkan Padding
//            cropRect = cropRect.insetBy(dx: -padding, dy: -padding)
//            let imageBounds = CGRect(origin: .zero, size: imageSize)
//            cropRect = cropRect.intersection(imageBounds)
//            
//            guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
//            return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
//            
//        } catch {
//            print("Vision error: \(error)")
//            return nil
//        }
//    }
    
    func cropToContentAccelerate(image: UIImage, padding: CGFloat, threshold: UInt8 = 245) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // Convert CGImage ke vImage_Buffer
        guard let buffer = try? vImage_Buffer(cgImage: cgImage) else { return nil }
        defer { buffer.free() }
        
        let width = Int(buffer.width)
        let height = Int(buffer.height)
        let rowBytes = buffer.rowBytes
        guard let data = buffer.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        
        var minX = width, maxX = 0
        var minY = height, maxY = 0
        var foundContent = false
        
        // Pemrosesan pointer langsung (meminimalisir overhead Swift boundary check)
        for y in 0..<height {
            let rowPtr = data.advanced(by: y * rowBytes)
            for x in 0..<width {
                let offset = x * 4 // Mengasumsikan RGBA 4 bytes
                let r = rowPtr[offset]
                let g = rowPtr[offset + 1]
                let b = rowPtr[offset + 2]
                
                if r < threshold || g < threshold || b < threshold {
                    foundContent = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        
        guard foundContent else { return nil }
        
        // Hitung Crop Box + Padding
        let paddingPx = Int(padding)
        let cropX = max(0, minX - paddingPx)
        let cropY = max(0, minY - paddingPx)
        let cropWidth = min(width - cropX, (maxX - minX) + paddingPx * 2)
        let cropHeight = min(height - cropY, (maxY - minY) + paddingPx * 2)
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    @objc private func actionPrint(){
        printPOS()
    }
}

extension ViewController: UITableViewDelegate, UITableViewDataSource{
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredPrinters.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PrinterCell", for: indexPath)
        cell.textLabel?.text = discoveredPrinters[indexPath.row].name
        cell.detailTextLabel?.text = discoveredPrinters[indexPath.row].identifier.uuidString
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        connect(to: discoveredPrinters[indexPath.row])
    }
}
extension ViewController{
    private var savedPrinterKey: String { "savedPrinterIdentifier" }
        
    // MARK: - Simpan printer setelah berhasil connect
    func savePrinterIdentifier(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedPrinterKey)
    }
    
    // MARK: - Ambil identifier tersimpan
    func getSavedPrinterIdentifier() -> UUID? {
        guard let idString = UserDefaults.standard.string(forKey: savedPrinterKey) else { return nil }
        return UUID(uuidString: idString)
    }
    
    // MARK: - Coba auto-reconnect
        func tryAutoReconnect() {
            guard centralManager.state == .poweredOn else {
                print("Bluetooth belum aktif")
                return
            }
            
            guard let savedID = getSavedPrinterIdentifier() else {
                print("Belum ada printer tersimpan, perlu scan manual")
                startScan()
                return
            }
            
            // Cari peripheral dari system cache pakai identifier
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [savedID])
            
            if let printer = peripherals.first {
                print("Printer ditemukan, mencoba connect: \(printer.name ?? "Unknown")")
                connect(to: printer)
            } else {
                print("Printer tersimpan tidak ditemukan (mungkin di luar jangkauan atau belum pernah pairing di sesi ini)")
            }
        }
        
        // MARK: - Alternatif: cari dari printer yang sedang connected di sistem
        func tryReconnectFromConnectedPeripherals() {
            guard let savedID = getSavedPrinterIdentifier() else { return }
            
            // Cek printer yang sudah "connected" di level sistem (misal masih nyambung dari app lain / sebelumnya)
            let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [])
            
            if let printer = connectedPeripherals.first(where: { $0.identifier == savedID }) {
                connect(to: printer)
            } else {
                tryAutoReconnect()
            }
        }
}
extension ViewController{
    private func sendDataInChunks(_ data: Data) {
        guard let peripheral = printerPeripheral, let characteristic = writeCharacteristic else {
            print("Peripheral atau characteristic belum siap")
            return
        }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        let mtu = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize = max(20, mtu)

        pendingChunks = stride(from: 0, to: data.count, by: chunkSize).map { offset in
            let end = min(offset + chunkSize, data.count)
            return data.subdata(in: offset..<end)
        }
        chunkIndex = 0
        isSending = true

        sendNextChunk(peripheral: peripheral, characteristic: characteristic, writeType: writeType)
    }

    private func sendNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic, writeType: CBCharacteristicWriteType) {
        if writeType == .withResponse {
            guard chunkIndex < pendingChunks.count else {
                finishSending()
                return
            }
            let chunk = pendingChunks[chunkIndex]
            chunkIndex += 1
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
            // lanjut di delegate didWriteValueFor
            return
        }

        // withoutResponse: kirim sebanyak mungkin selama buffer BLE masih siap
        while chunkIndex < pendingChunks.count {
            guard peripheral.canSendWriteWithoutResponse else {
                // stack lagi penuh, nunggu delegate peripheralIsReady(toSendWriteWithoutResponse:)
                return
            }
            let chunk = pendingChunks[chunkIndex]
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            chunkIndex += 1
        }

        finishSending()
    }

    private func finishSending() {
        isSending = false
        pendingChunks.removeAll()
        chunkIndex = 0
        print("Selesai kirim data ke printer")
    }
    // MARK: - CBPeripheralDelegate
    // Dipanggil setelah writeWithResponse sukses -> lanjut chunk berikutnya
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Gagal kirim chunk: \(error)")
            isSending = false
            return
        }
        guard let writeCharacteristic = writeCharacteristic, characteristic == writeCharacteristic else { return }
        sendNextChunk(peripheral: peripheral, characteristic: characteristic, writeType: .withResponse)
    }

    // dipanggil saat buffer BLE longgar lagi, khusus withoutResponse
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let characteristic = writeCharacteristic else { return }
        sendNextChunk(peripheral: peripheral, characteristic: characteristic, writeType: .withoutResponse)
    }
}
