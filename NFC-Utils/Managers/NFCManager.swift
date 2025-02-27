import Foundation
import CoreNFC

@MainActor
class NFCManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var message = "Ready to scan"
    
    private var session: NFCTagReaderSession?
    private var dataToWrite: [UInt8] = []
    
    func startScanning(data: [UInt8]) {
        guard NFCTagReaderSession.readingAvailable else {
            message = "NFC is not available on this device"
            return
        }
        
        self.dataToWrite = data
        self.isScanning = true
        
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        session?.alertMessage = "Hold your iPhone near an NFC tag"
        session?.begin()
    }
}

extension NFCManager: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session is active, ready to scan tags
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Check if the session was invalidated due to user cancellation
        if let readerError = error as? NFCReaderError, 
           readerError.code == .readerSessionInvalidationErrorUserCanceled {
            Task { @MainActor in
                self.message = "Scanning canceled"
                self.isScanning = false
            }
        } else {
            Task { @MainActor in
                self.message = "Error: \(error.localizedDescription)"
                self.isScanning = false
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { 
            session.invalidate(errorMessage: "No tag found")
            return 
        }
        
        // Connect to the first detected tag
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            // Process the tag based on its type
            switch tag {
            case .miFare(let mifareTag):
                self.writeDataToMiFare(session: session, tag: mifareTag)
            case .iso7816(let iso7816Tag):
                self.writeDataToISO7816(session: session, tag: iso7816Tag)
            case .feliCa(let felicaTag):
                self.writeDataToFeliCa(session: session, tag: felicaTag)
            case .iso15693(let iso15693Tag):
                self.writeDataToISO15693(session: session, tag: iso15693Tag)
            @unknown default:
                session.invalidate(errorMessage: "Unsupported tag type")
            }
        }
    }
    
    private func writeDataToMiFare(session: NFCTagReaderSession, tag: NFCMiFareTag) {
        // MiFare tags use simple read/write commands with block addressing
        let blockNumber: UInt8 = 0x04 // We'll start writing at block 4 (usually first usable data block)
        
        // Break data into blocks as needed
        let blockSize = 4 // MiFare Classic blocks are 4 bytes
        var blockData: [[UInt8]] = []
        
        // Split data into block-sized chunks
        for i in stride(from: 0, to: dataToWrite.count, by: blockSize) {
            let endIndex = Swift.min(i + blockSize, dataToWrite.count)
            let chunk = Array(dataToWrite[i..<endIndex])
            // Pad with zeros if needed
            let paddedChunk = chunk + Array(repeating: 0, count: blockSize - chunk.count)
            blockData.append(paddedChunk)
        }
        
        // Write each block sequentially
        self.writeNextBlock(session: session, tag: tag, blockNumber: blockNumber, blockData: blockData, currentIndex: 0)
    }
    
    private func writeNextBlock(session: NFCTagReaderSession, tag: NFCMiFareTag, blockNumber: UInt8, blockData: [[UInt8]], currentIndex: Int) {
        guard currentIndex < blockData.count else {
            // We've written all blocks
            session.alertMessage = "Data written successfully"
            session.invalidate()
            Task { @MainActor in
                self.message = "Data written successfully"
                self.isScanning = false
            }
            return
        }
        
        // Calculate the current block to write
        let currentBlockNumber = blockNumber + UInt8(currentIndex)
        let currentData = blockData[currentIndex]
        
        // Command for writing a block to MiFare Classic
        let writeCommand = [UInt8(0xA2), currentBlockNumber] + currentData
        
        tag.sendMiFareCommand(commandPacket: Data(writeCommand)) { data, error in
            if let error = error {
                session.invalidate(errorMessage: "Write error: \(error.localizedDescription)")
                return
            }
            
            // Write next block
            self.writeNextBlock(session: session, tag: tag, blockNumber: blockNumber, blockData: blockData, currentIndex: currentIndex + 1)
        }
    }
    
    private func writeDataToISO7816(session: NFCTagReaderSession, tag: NFCISO7816Tag) {
        // This is a simplified example - actual implementation depends on the specific card type
        session.invalidate(errorMessage: "ISO7816 tag writing not fully implemented")
    }
    
    private func writeDataToFeliCa(session: NFCTagReaderSession, tag: NFCFeliCaTag) {
        // FeliCa writing requires specific service/block addressing
        session.invalidate(errorMessage: "FeliCa tag writing not fully implemented")
    }
    
    private func writeDataToISO15693(session: NFCTagReaderSession, tag: NFCISO15693Tag) {
        // Writing to ISO15693 tags
        let blockSize = 4 // Typical block size
        var blockIndex = 0
        
        func writeNextBlock() {
            // Check if we have more data to write
            let startIndex = blockIndex * blockSize
            guard startIndex < self.dataToWrite.count else {
                session.alertMessage = "Data written successfully"
                session.invalidate()
                Task { @MainActor in
                    self.message = "Data written successfully"
                    self.isScanning = false
                }
                return
            }
            
            // Get data for this block
            let endIndex = min(startIndex + blockSize, self.dataToWrite.count)
            let blockData = Array(self.dataToWrite[startIndex..<endIndex])
            // Pad to block size if necessary
            let paddedData = blockData + Array(repeating: UInt8(0), count: blockSize - blockData.count)
            
            // Write block
            tag.writeMultipleBlocks(requestFlags: .highDataRate, blockRange: NSRange(location: blockIndex, length: 1), dataBlocks: Data(paddedData)) { error in
                if let error = error {
                    session.invalidate(errorMessage: "Write error: \(error.localizedDescription)")
                    return
                }
                
                // Move to next block
                blockIndex += 1
                writeNextBlock()
            }
        }
        
        // Start writing blocks
        writeNextBlock()
    }
}
