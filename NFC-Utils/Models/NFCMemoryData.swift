import Foundation
import SwiftData

@Model
final class NFCMemoryData {
    var name: String
    var data: String
    var timestamp: Date
    
    init(name: String, data: String, timestamp: Date = Date()) {
        self.name = name
        self.data = data
        self.timestamp = timestamp
    }
    
    // Convert colon-separated string to byte array
    func toByteArray() -> [UInt8] {
        let components = data.split(separator: ":")
        return components.compactMap { UInt8($0, radix: 16) }
    }
}
