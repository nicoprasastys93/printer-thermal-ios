//
//  ViewController.swift
//  Printer Thermal
//
//  Created by NPSK Macbook on 29/07/26.
//

import UIKit
import CoreBluetooth
import Accelerate

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
        
        tryAutoReconnect()
        
        if let decodData = Data(base64Encoded: base64String){
            imageFromPDFData(decodData){ image in
                if let image = image{
                    DispatchQueue.main.async {
                        self.imageView.image = image
                    }
                    EscPosImageConverter.convertToEscPosData(image, maxWidth: 576) { data in
                        DispatchQueue.global(qos: .utility).async {
                            guard let data = data else {return}
                            self.sendDataInChunks(data)
                        }
                    }
                }
            }
        }
    }
    func imageFromPDFData(_ data: Data, completion: @escaping((_ image: UIImage?)-> Void)){
        DispatchQueue.global(qos: .utility).async{
            let timeStart = CFAbsoluteTimeGetCurrent()
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
            let timeEnd = CFAbsoluteTimeGetCurrent()
            let timeResult = timeEnd - timeStart
            print("========PROSES PDF TO IMAGE========")
            print("Background Process")
            print("Finish Add => \(timeResult) detik")
            
            self.cropToContentAccelerate(image: image, padding: 0){ image in
                completion(image)
            }
        }
    }
    
    func cropToContentAccelerate(image: UIImage, padding: CGFloat, threshold: UInt8 = 245, completion: @escaping((_ image: UIImage?) -> Void)) {
        DispatchQueue.global(qos: .utility).async {
            let timeStart = CFAbsoluteTimeGetCurrent()

            guard let cgImage = image.cgImage else {
                completion(nil)
                return
            }

            guard let buffer = try? vImage_Buffer(cgImage: cgImage) else {
                completion(nil)
                return
            }
            defer { buffer.free() }

            let width = Int(buffer.width)
            let height = Int(buffer.height)
            let rowBytes = buffer.rowBytes
            guard let data = buffer.data?.assumingMemoryBound(to: UInt8.self) else {
                completion(nil)
                return
            }

            // cek apakah 1 baris punya konten
            func rowHasContent(_ y: Int) -> Bool {
                let rowPtr = data.advanced(by: y * rowBytes)
                var x = 0
                while x < width {
                    let offset = x * 4
                    if rowPtr[offset] < threshold || rowPtr[offset + 1] < threshold || rowPtr[offset + 2] < threshold {
                        return true
                    }
                    x += 1
                }
                return false
            }

            // cek apakah 1 kolom (dalam rentang y tertentu) punya konten
            func colHasContent(_ x: Int, yRange: ClosedRange<Int>) -> Bool {
                let offset = x * 4
                for y in yRange {
                    let rowPtr = data.advanced(by: y * rowBytes)
                    if rowPtr[offset] < threshold || rowPtr[offset + 1] < threshold || rowPtr[offset + 2] < threshold {
                        return true
                    }
                }
                return false
            }

            // 1. cari minY (scan dari atas)
            var minY = 0
            while minY < height && !rowHasContent(minY) { minY += 1 }

            guard minY < height else {
                completion(nil) // gambar polos/kosong
                return
            }

            // 2. cari maxY (scan dari bawah)
            var maxY = height - 1
            while maxY > minY && !rowHasContent(maxY) { maxY -= 1 }

            // 3. cari minX (scan dari kiri, hanya di rentang minY...maxY)
            var minX = 0
            while minX < width && !colHasContent(minX, yRange: minY...maxY) { minX += 1 }

            // 4. cari maxX (scan dari kanan)
            var maxX = width - 1
            while maxX > minX && !colHasContent(maxX, yRange: minY...maxY) { maxX -= 1 }

            // Hitung Crop Box + Padding
            let paddingPx = Int(padding)
            let cropX = max(0, minX - paddingPx)
            let cropY = max(0, minY - paddingPx)
            let cropWidth = min(width - cropX, (maxX - minX) + paddingPx * 2)
            let cropHeight = min(height - cropY, (maxY - minY) + paddingPx * 2)

            let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

            guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                completion(nil)
                return
            }

            let timeEnd = CFAbsoluteTimeGetCurrent()
            print("========PROSES IMAGE CROP========")
            print("Background Process")
            print("Finish Add    => \(timeEnd - timeStart) detik")
            completion(UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation))
        }
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
            // lanjut di delegate didWriteValueForm
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
