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
        return scanAllFields(in: data, depth: 0)
    }
    
    private func scanAllFields(in data: Data, depth: Int) -> String? {
        var offset = 0
        var foundToken: String? = nil
        
        while offset < data.count {
            let (tagWire, _) = readVarint(data, at: &offset)
            let wireType = Int(tagWire & 0x07)
            let fieldNumber = Int(tagWire >> 3)
            
            if wireType == 2 {
                let (length, _) = readVarint(data, at: &offset)
                var extraInfo = ""
                
                if offset + Int(length) > data.count {
                    #if DEBUG
                    print("AntigravityCredentialProvider: [Depth \(depth)] field=\(fieldNumber) wireType=\(wireType) len=\(length) - ERROR: truncated")
                    #endif
                    break
                }
                
                let fieldData = data.subdata(in: offset..<offset+Int(length))
                
                let utf8Str = String(data: fieldData, encoding: .utf8)
                let isUtf8 = (utf8Str != nil)
                let hasYa29 = utf8Str?.contains("ya29.") ?? false
                
                #if DEBUG
                print("AntigravityCredentialProvider: [Depth \(depth)] field=\(fieldNumber) len=\(length) isUtf8=\(isUtf8) hasYa29=\(hasYa29)")
                #endif
                
                if hasYa29 {
                    if let json = try? JSONSerialization.jsonObject(with: fieldData, options: []) as? [String: Any] {
                        let candidateToken = (json["access_token"] as? String) ?? (json["accessToken"] as? String)
                        
                        if let token = candidateToken, token.hasPrefix("ya29.") {
                            #if DEBUG
                            print("AntigravityCredentialProvider: Successfully extracted and validated JSON access token!")
                            #endif
                            if foundToken == nil {
                                foundToken = token
                            }
                        }
                    }
                }
                
                // Recurse into this field if we haven't found a token yet
                if foundToken == nil, let nestedToken = scanAllFields(in: fieldData, depth: depth + 1) {
                    foundToken = nestedToken
                }
                
                offset += Int(length)
            } else if wireType == 0 {
                let _ = readVarint(data, at: &offset)
                #if DEBUG
                print("AntigravityCredentialProvider: [Depth \(depth)] field=\(fieldNumber) wireType=\(wireType)")
                #endif
            } else if wireType == 1 {
                offset += 8
                #if DEBUG
                print("AntigravityCredentialProvider: [Depth \(depth)] field=\(fieldNumber) wireType=\(wireType)")
                #endif
            } else if wireType == 5 {
                offset += 4
                #if DEBUG
                print("AntigravityCredentialProvider: [Depth \(depth)] field=\(fieldNumber) wireType=\(wireType)")
                #endif
            } else {
                break
            }
        }
        
        return foundToken
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
