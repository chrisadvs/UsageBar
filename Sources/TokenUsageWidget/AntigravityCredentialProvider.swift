import Foundation
import SQLite3

public class AntigravityCredentialProvider: CredentialProvider {
    private var manualToken: String?
    
    public init() {}
    
    public func getCredential() async -> String? {
        // Debug fallback
        if let manualToken = manualToken {
            return manualToken
        }
        
        let dbPath = NSString(string: "~/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb").expandingTildeInPath
        
        guard let base64String = readOauthToken(dbPath: dbPath) else {
            return nil
        }
        
        guard let data = Data(base64Encoded: base64String) else {
            return nil
        }
        
        return extractAccessToken(from: data)
    }
    
    public func saveCredential(_ credential: String) {
        self.manualToken = credential
    }
    
    private func readOauthToken(dbPath: String) -> String? {
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            return nil
        }
        defer { sqlite3_close(db) }
        
        let query = "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken';"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) != SQLITE_OK {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                return String(cString: cString)
            }
        }
        return nil
    }
    
    private func extractAccessToken(from data: Data) -> String? {
        var offset = 0
        var foundCount = 0
        
        while offset < data.count {
            let (tagWire, _) = readVarint(data, at: &offset)
            let wireType = Int(tagWire & 0x07)
            
            if wireType == 2 { // length-delimited
                let (length, _) = readVarint(data, at: &offset)
                
                if offset + Int(length) > data.count {
                    break
                }
                
                let fieldData = data.subdata(in: offset..<offset+Int(length))
                foundCount += 1
                
                #if DEBUG
                print("AntigravityCredentialProvider: Found top-level field \(foundCount), length: \(length)")
                #endif
                
                if let token = searchForAuthSubstructure(in: fieldData) {
                    return token
                }
                
                offset += Int(length)
            } else if wireType == 0 { // varint
                let _ = readVarint(data, at: &offset)
            } else if wireType == 1 { // 64-bit
                offset += 8
            } else if wireType == 5 { // 32-bit
                offset += 4
            } else {
                break
            }
        }
        return nil
    }
    
    private func searchForAuthSubstructure(in data: Data) -> String? {
        var offset = 0
        var accessToken: String? = nil
        var foundTag2 = false
        var foundTag3 = false
        var foundTag4 = false
        
        var fieldsFound = 0
        
        while offset < data.count {
            let (tagWire, _) = readVarint(data, at: &offset)
            let wireType = Int(tagWire & 0x07)
            let fieldNumber = Int(tagWire >> 3)
            
            if wireType == 2 {
                let (length, _) = readVarint(data, at: &offset)
                
                if offset + Int(length) > data.count {
                    break
                }
                
                let fieldData = data.subdata(in: offset..<offset+Int(length))
                
                if fieldNumber == 1 {
                    if let str = String(data: fieldData, encoding: .utf8), str.hasPrefix("ya29.") {
                        accessToken = str
                    }
                } else if fieldNumber == 2 {
                    if let str = String(data: fieldData, encoding: .utf8), str == "Bearer" {
                        foundTag2 = true
                    }
                } else if fieldNumber == 3 {
                    if let str = String(data: fieldData, encoding: .utf8), str.hasPrefix("1//") {
                        foundTag3 = true
                    }
                } else if fieldNumber == 4 {
                    foundTag4 = true
                }
                
                fieldsFound += 1
                offset += Int(length)
            } else if wireType == 0 {
                let _ = readVarint(data, at: &offset)
            } else if wireType == 1 {
                offset += 8
            } else if wireType == 5 {
                offset += 4
            } else {
                break
            }
        }
        
        #if DEBUG
        if fieldsFound > 0 {
            print("AntigravityCredentialProvider: Substructure Check - fields: \(fieldsFound), hasYa29: \(accessToken != nil), hasBearer: \(foundTag2), hasRefresh: \(foundTag3), hasExpiry: \(foundTag4)")
        }
        #endif
        
        if accessToken != nil && foundTag2 && foundTag3 {
            return accessToken
        }
        
        // Recursive search deeper if not found in this layer
        offset = 0
        while offset < data.count {
            let (tagWire, _) = readVarint(data, at: &offset)
            let wireType = Int(tagWire & 0x07)
            if wireType == 2 {
                let (length, _) = readVarint(data, at: &offset)
                if offset + Int(length) <= data.count {
                    let fieldData = data.subdata(in: offset..<offset+Int(length))
                    if let token = searchForAuthSubstructure(in: fieldData) {
                        return token
                    }
                }
                offset += Int(length)
            } else if wireType == 0 {
                let _ = readVarint(data, at: &offset)
            } else if wireType == 1 {
                offset += 8
            } else if wireType == 5 {
                offset += 4
            } else {
                break
            }
        }
        
        return nil
    }
    
    private func readVarint(_ data: Data, at offset: inout Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            bytesRead += 1
            
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                break
            }
            shift += 7
            
            if shift >= 64 {
                break
            }
        }
        return (result, bytesRead)
    }
}
