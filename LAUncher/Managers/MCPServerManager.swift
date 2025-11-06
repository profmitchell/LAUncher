import Foundation
import Combine
import AVFoundation
import AudioToolbox
import Darwin

@MainActor
final class MCPServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 5555
    
    private var listener: SocketListener?
    private weak var session: PluginHostSession?
    private var serverTask: Task<Void, Never>?
    
    init(session: PluginHostSession) {
        self.session = session
    }
    
    func start() throws {
        guard !isRunning else { 
            print("⚠️ MCP server already running")
            return 
        }
        
        let listener = SocketListener(port: port, session: session!)
        try listener.start()
        self.listener = listener
        
        // Start server on background thread
        serverTask = Task.detached(priority: .background) { [weak self] in
            await self?.runServer()
        }
        
        isRunning = true
        print("✅ MCP HTTP Server started on port \(port)")
    }
    
    private func runServer() async {
        // Keep server running
        while isRunning {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        listener?.stop()
        listener = nil
        serverTask?.cancel()
        serverTask = nil
        print("🛑 MCP HTTP Server stopped")
    }
}

private class SocketListener {
    let port: Int
    weak var session: PluginHostSession?
    private var socket: Int32 = -1
    private var isStopped = false
    
    init(port: Int, session: PluginHostSession) {
        self.port = port
        self.session = session
    }
    
    func start() throws {
        var hints = addrinfo(
            ai_flags: AI_PASSIVE,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        
        var result: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        
        let status = getaddrinfo(nil, portString, &hints, &result)
        guard status == 0, let addr = result else {
            throw NSError(domain: "MCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get address info"])
        }
        
        socket = Darwin.socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
        guard socket >= 0 else {
            freeaddrinfo(result)
            throw NSError(domain: "MCPServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var reuse = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int>.size))
        
        // Make socket non-blocking
        var flags = fcntl(socket, F_GETFL, 0)
        _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        
        let bindStatus = bind(socket, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
        guard bindStatus == 0 else {
            freeaddrinfo(result)
            close(socket)
            throw NSError(domain: "MCPServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"])
        }
        
        freeaddrinfo(result)
        
        let listenStatus = listen(socket, 5)
        guard listenStatus == 0 else {
            close(socket)
            throw NSError(domain: "MCPServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }
        
        // Start accepting connections in background
        Task.detached { [weak self] in
            await self?.acceptConnections()
        }
    }
    
    private func acceptConnections() async {
        while !isStopped {
            var addr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            
            let clientSocket = accept(socket, &addr, &len)
            
            if clientSocket >= 0 {
                // Got a connection
                Task.detached { [weak self] in
                    await self?.handleConnection(clientSocket: clientSocket)
                }
            } else {
                // No connection available (non-blocking), sleep briefly
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
    
    private func handleConnection(clientSocket: Int32) async {
        defer { close(clientSocket) }
        
        var buffer = [UInt8](repeating: 0, count: 8192)
        
        // Set socket to non-blocking for read
        var flags = fcntl(clientSocket, F_GETFL, 0)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)
        
        var totalRead = 0
        var attempts = 0
        let maxAttempts = 100 // 1 second max wait
        
        // Read request in chunks (non-blocking)
        while attempts < maxAttempts {
            let bytesRead = recv(clientSocket, &buffer[totalRead], 8192 - totalRead, 0)
            
            if bytesRead > 0 {
                totalRead += bytesRead
                if totalRead >= 8192 {
                    break
                }
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // No data available yet, wait a bit
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                attempts += 1
            } else {
                // Error or connection closed
                break
            }
        }
        
        guard totalRead > 0 else { return }
        
        guard let requestString = String(bytes: buffer.prefix(totalRead), encoding: .utf8) else { return }
        
        let response = await handleRequest(requestString)
        
        let responseData = response.data(using: .utf8) ?? Data()
        _ = responseData.withUnsafeBytes { bytes in
            send(clientSocket, bytes.baseAddress, responseData.count, 0)
        }
    }
    
    private func handleRequest(_ request: String) async -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpResponse(status: "400 Bad Request", body: "Invalid request")
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 3 else {
            return httpResponse(status: "400 Bad Request", body: "Invalid request line")
        }
        
        let method = components[0]
        let path = components[1]
        
        // Parse JSON body if present
        var jsonBody: [String: Any]?
        if let bodyStart = request.range(of: "\r\n\r\n") {
            let bodyString = String(request[bodyStart.upperBound...])
            if let data = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                jsonBody = json
            }
        }
        
        // Route requests
        if method == "POST" && path == "/api/get_parameters" {
            return handleGetParameters(jsonBody)
        } else if method == "POST" && path == "/api/set_parameters" {
            return await handleSetParameters(jsonBody)
        } else if method == "POST" && path == "/api/randomize_parameters" {
            return await handleRandomizeParameters(jsonBody)
        } else if method == "GET" && path == "/health" {
            return httpResponse(status: "200 OK", body: "OK")
        } else {
            return httpResponse(status: "404 Not Found", body: "Not Found")
        }
    }
    
    private func handleGetParameters(_ body: [String: Any]?) -> String {
        guard let session = session,
              let params = session.getCurrentParameters() else {
            return jsonResponse([
                "plugin": "Unknown",
                "parameters": []
            ])
        }
        
        let mcpParams = params.map { param -> [String: Any] in
            [
                "id": param.identifier,
                "path": param.displayName,
                "address": param.address,
                "displayName": param.displayName,
                "min": Double(param.minValue),
                "max": Double(param.maxValue),
                "unit": "",
                "value": Double(param.value)
            ]
        }
        
        return jsonResponse([
            "plugin": session.currentComponent?.name ?? "Unknown",
            "parameters": mcpParams
        ])
    }
    
    private func handleSetParameters(_ body: [String: Any]?) async -> String {
        guard let session = session,
              let changes = body?["changes"] as? [[String: Any]] else {
            return jsonResponse(["result": "error", "message": "No changes provided"])
        }
        
        var applied: [[String: Any]] = []
        
        for change in changes {
            guard let id = change["id"] as? String,
                  let value = change["value"] as? Double else {
                continue
            }
            
            // Try to find parameter by identifier or display name
            if session.setParameterValue(identifier: id, value: value) ||
               session.setParameterValue(displayName: id, value: value) {
                applied.append(["id": id, "value": value])
            }
        }
        
        return jsonResponse([
            "result": "ok",
            "applied": applied
        ])
    }
    
    private func handleRandomizeParameters(_ body: [String: Any]?) async -> String {
        guard let session = session else {
            return jsonResponse(["result": "error", "message": "No session"])
        }
        
        let intensity = (body?["intensity"] as? Double) ?? 0.4
        let preserveCategories = (body?["preserveCategories"] as? [String]) ?? []
        
        do {
            let result = try await session.randomizeParameters(
                intensity: intensity,
                preserveCategories: preserveCategories
            )
            
            return jsonResponse([
                "result": "ok",
                "intensity": result.intensity,
                "randomizedCount": result.randomizedCount
            ])
        } catch {
            return jsonResponse([
                "result": "error",
                "message": error.localizedDescription
            ])
        }
    }
    
    private func httpResponse(status: String, body: String) -> String {
        let contentLength = body.utf8.count
        return """
        HTTP/1.1 \(status)
        Content-Type: application/json
        Content-Length: \(contentLength)
        Access-Control-Allow-Origin: *
        
        \(body)
        """
    }
    
    private func jsonResponse(_ data: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return httpResponse(status: "500 Internal Server Error", body: "{\"error\":\"Failed to serialize\"}")
        }
        return httpResponse(status: "200 OK", body: jsonString)
    }
    
    func stop() {
        isStopped = true
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }
}

