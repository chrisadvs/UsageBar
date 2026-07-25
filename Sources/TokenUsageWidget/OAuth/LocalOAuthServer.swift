import Foundation
import Darwin

class LocalOAuthServer {
    private var serverSocket: Int32 = -1
    private(set) var port: UInt16 = 0
    var onCodeReceived: ((String) -> Void)?
    private var isListening = false
    
    func start() throws -> UInt16 {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw NSError(domain: "LocalOAuthServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"]) }
        
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0) // dynamic port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        var bindResult: Int32 = -1
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bindResult = bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else { throw NSError(domain: "LocalOAuthServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"]) }
        guard listen(serverSocket, 1) >= 0 else { throw NSError(domain: "LocalOAuthServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"]) }
        
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(serverSocket, sockPtr, &len)
            }
        }
        
        self.port = UInt16(bigEndian: addr.sin_port)
        self.isListening = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
        
        return self.port
    }
    
    private func acceptLoop() {
        while isListening {
            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else { continue }
            
            var buffer = [UInt8](repeating: 0, count: 4096)
            let readLen = recv(client, &buffer, buffer.count, 0)
            if readLen > 0 {
                let requestString = String(bytes: buffer[0..<readLen], encoding: .utf8) ?? ""
                
                if requestString.hasPrefix("GET /oauth-callback"), let firstLine = requestString.components(separatedBy: "\r\n").first {
                    let parts = firstLine.components(separatedBy: " ")
                    if parts.count >= 2 {
                        let path = parts[1]
                        if let url = URL(string: "http://localhost\(path)"),
                           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                            
                            let responseBody = "<html><body><h2>Login successful</h2><p>You can close this window now.</p></body></html>"
                            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(responseBody.utf8.count)\r\nConnection: close\r\n\r\n\(responseBody)"
                            
                            response.withCString { ptr in
                                send(client, ptr, Int(strlen(ptr)), 0)
                            }
                            
                            close(client)
                            
                            DispatchQueue.main.async {
                                self.onCodeReceived?(code)
                            }
                            self.stop()
                            continue
                        }
                    }
                }
            }
            close(client)
        }
    }
    
    func stop() {
        isListening = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
}
