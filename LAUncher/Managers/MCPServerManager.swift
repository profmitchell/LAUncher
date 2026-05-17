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

        isRunning = true

        // Keep run loop alive (must set isRunning before scheduling so the first tick sees true)
        serverTask = Task.detached(priority: .background) { [weak self] in
            await self?.runServer()
        }

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
        let flags = fcntl(socket, F_GETFL, 0)
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
        let flags = fcntl(clientSocket, F_GETFL, 0)
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
        
        let responseData = await handleRequest(requestString)

        // send() often returns before the whole buffer is written; large JSON (get_parameters)
        // would truncate and clients see "socket hang up". Block and loop until drained.
        let cleared = fcntl(clientSocket, F_GETFL, 0)
        _ = fcntl(clientSocket, F_SETFL, cleared & ~O_NONBLOCK)

        responseData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let total = responseData.count
            while offset < total {
                let written = send(clientSocket, base.advanced(by: offset), total - offset, 0)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }
    
    private func handleRequest(_ request: String) async -> Data {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpPlainResponse(status: "400 Bad Request", body: "Invalid request")
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 3 else {
            return httpPlainResponse(status: "400 Bad Request", body: "Invalid request line")
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
            return await handleGetParameters(jsonBody)
        } else if method == "POST" && path == "/api/set_parameters" {
            return await handleSetParameters(jsonBody)
        } else if method == "POST" && path == "/api/randomize_parameters" {
            return await handleRandomizeParameters(jsonBody)
        } else if method == "POST" && path == "/api/analyze_patch" {
            return await handleAnalyzePatch(jsonBody)
        } else if method == "POST" && path == "/api/create_midi_mapping" {
            return await handleCreateMIDIMapping(jsonBody)
        } else if method == "POST" && path == "/api/chat" {
            return await handleChat(jsonBody)
        } else if method == "GET" && path == "/health" {
            return httpPlainResponse(status: "200 OK", body: "OK")
        } else {
            return httpPlainResponse(status: "404 Not Found", body: "Not Found")
        }
    }
    
    private func handleGetParameters(_ body: [String: Any]?) async -> Data {
        await MainActor.run { [weak session] in
            guard let session,
                  let params = session.getCurrentParameters() else {
                return jsonResponse([
                    "plugin": "Unknown",
                    "parameters": [],
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
                    "value": Double(param.value),
                ]
            }

            return jsonResponse([
                "plugin": session.currentComponent?.name ?? "Unknown",
                "parameters": mcpParams,
            ])
        }
    }
    
    private func handleSetParameters(_ body: [String: Any]?) async -> Data {
        guard let changes = body?["changes"] as? [[String: Any]] else {
            return jsonResponse(["result": "error", "message": "No changes provided"])
        }
        return await MainActor.run { [weak session] in
            guard let session else {
                return jsonResponse(["result": "error", "message": "No session"])
            }
            var applied: [[String: Any]] = []
            for change in changes {
                guard let id = change["id"] as? String,
                      let value = change["value"] as? Double else {
                    continue
                }
                if session.setParameterValue(identifier: id, value: value)
                    || session.setParameterValue(displayName: id, value: value) {
                    applied.append(["id": id, "value": value])
                }
            }
            return jsonResponse([
                "result": "ok",
                "applied": applied,
            ])
        }
    }

    private func handleAnalyzePatch(_ body: [String: Any]?) async -> Data {
        _ = body
        return await Task { @MainActor [weak session] in
            guard let session else {
                return jsonResponse(["result": "error", "message": "No session"])
            }
            do {
                let analysis = try await session.exportPatchAnalysisContext()
                return jsonResponse(["result": "ok", "analysis": analysis])
            } catch {
                return jsonResponse(["result": "error", "message": error.localizedDescription])
            }
        }.value
    }

    private func handleRandomizeParameters(_ body: [String: Any]?) async -> Data {
        let intensity = (body?["intensity"] as? Double) ?? 0.4
        let preserveCategories = (body?["preserveCategories"] as? [String]) ?? []
        return await Task { @MainActor [weak session] in
            guard let session else {
                return jsonResponse(["result": "error", "message": "No session"])
            }
            do {
                let result = try await session.randomizeParameters(
                    intensity: intensity,
                    preserveCategories: preserveCategories
                )
                return jsonResponse([
                    "result": "ok",
                    "intensity": result.intensity,
                    "randomizedCount": result.randomizedCount,
                ])
            } catch {
                return jsonResponse([
                    "result": "error",
                    "message": error.localizedDescription,
                ])
            }
        }.value
    }

    private func handleCreateMIDIMapping(_ body: [String: Any]?) async -> Data {
        guard let ccNumber = body?["ccNumber"] as? Int,
              let parameterIds = body?["parameterIds"] as? [String] else {
            return jsonResponse(["result": "error", "message": "Missing ccNumber or parameterIds"])
        }
        return await MainActor.run { [weak session] in
            guard let session else {
                return jsonResponse(["result": "error", "message": "No session"])
            }
            var created: [[String: Any]] = []
            for paramId in parameterIds {
                guard let param = session.findParameter(identifier: paramId) else {
                    continue
                }
                session.midiMapManager.createMapping(
                    parameterId: paramId,
                    parameterDisplayName: param.displayName,
                    ccNumber: UInt8(ccNumber),
                    minValue: param.minValue,
                    maxValue: param.maxValue
                )
                created.append([
                    "parameterId": paramId,
                    "displayName": param.displayName,
                    "ccNumber": ccNumber,
                ])
            }
            return jsonResponse([
                "result": "ok",
                "created": created,
            ])
        }
    }
    
    private func handleChat(_ body: [String: Any]?) async -> Data {
        guard let message = body?["message"] as? String else {
            return jsonResponse(["response": "I need a message to respond to."])
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            Task { @MainActor [weak self, weak session] in
                guard let self, let session else {
                    continuation.resume(returning: jsonResponse(["response": "Session unavailable."]))
                    return
                }
                let lowerMessage = message.lowercased()
                var response = ""

                // Parse natural language commands
        if lowerMessage.contains("set") || lowerMessage.contains("change") {
            // Parameter setting commands
            if lowerMessage.contains("filter") && lowerMessage.contains("cutoff") {
                // Extract value
                let numbers = extractNumbers(from: message)
                if let value = numbers.first {
                    let filterIds = session.analyzedParameters?.filterCutoffIds ?? []
                    if let filterId = filterIds.first {
                        let success = session.setParameterValue(identifier: filterId, value: Double(value))
                        if success {
                            response = "✅ Set Filter Cutoff to \(value) Hz"
                        } else {
                            response = "❌ Failed to set filter cutoff"
                        }
                    } else {
                        response = "❌ Couldn't find filter cutoff parameter"
                    }
                } else {
                    response = "I need a value. Try: \"Set filter cutoff to 2000\""
                }
            } else if lowerMessage.contains("oscillator") || lowerMessage.contains("osc") {
                // Oscillator level commands
                let oscNumbers = extractOscillatorNumbers(from: message)
                let numbers = extractNumbers(from: message)
                
                if let level = numbers.first {
                    var successCount = 0
                    let oscIds = session.analyzedParameters?.oscillatorLevelIds ?? []
                    
                    for oscNum in oscNumbers {
                        if oscNum <= oscIds.count {
                            let paramId = oscIds[oscNum - 1]
                            if session.setParameterValue(identifier: paramId, value: Double(level)) {
                                successCount += 1
                            }
                        }
                    }
                    if successCount > 0 {
                        response = "✅ Set \(successCount) oscillator level(s) to \(level)"
                    } else {
                        response = "❌ Couldn't find oscillator level parameters"
                    }
                } else {
                    response = "I need a level value. Try: \"Set oscillator 1 level to 0.8\""
                }
            } else {
                // Generic parameter setting
                response = "I can set filter cutoff, oscillator levels, and other parameters. Try: \"Set filter cutoff to 2000\""
            }
        } else if lowerMessage.contains("map") || lowerMessage.contains("assign") {
            // MIDI mapping commands
            if lowerMessage.contains("modwheel") || lowerMessage.contains("mod wheel") || lowerMessage.contains("cc 1") {
                if lowerMessage.contains("oscillator") || lowerMessage.contains("osc") {
                    // Check if they want internal modulation (Vital's mod matrix) vs MIDI CC mapping
                    if lowerMessage.contains("source") || lowerMessage.contains("in vital") || lowerMessage.contains("modulation") || lowerMessage.contains("matrix") {
                        // Internal modulation routing in Vital/Serum
                        response = await self.setupModwheelModulation(session: session, targetOscillators: [1, 2, 3])
                    } else {
                        // MIDI CC mapping (existing behavior)
                        let oscIds = session.analyzedParameters?.oscillatorLevelIds ?? ["50797", "51513", "52503"] // Fallback to Vital IDs
                        for paramId in oscIds {
                            if let param = session.findParameter(identifier: paramId) {
                                session.midiMapManager.createMapping(
                                    parameterId: paramId,
                                    parameterDisplayName: param.displayName,
                                    ccNumber: 1,
                                    minValue: param.minValue,
                                    maxValue: param.maxValue
                                )
                            }
                        }
                        response = "✅ Mapped modwheel (CC 1) to all oscillator levels!"
                    }
                } else {
                    response = "What should I map modwheel to? Try: \"Map modwheel to all oscillators\" or \"Map modwheel as source to oscillator levels\""
                }
            } else {
                response = "I can map MIDI controllers. Try: \"Map modwheel to all oscillators\""
            }
        } else if lowerMessage.contains("randomize") || lowerMessage.contains("random") {
            // Randomize parameters
            do {
                let result = try await session.randomizeParameters(intensity: 0.4)
                response = "🎲 Randomized \(result.randomizedCount) parameters with intensity \(result.intensity)"
            } catch {
                response = "❌ Failed to randomize: \(error.localizedDescription)"
            }
        } else if lowerMessage.contains("get") || lowerMessage.contains("show") || lowerMessage.contains("list") {
            // Get information
            if lowerMessage.contains("oscillator") || lowerMessage.contains("osc") {
                let oscParams = session.getOscillatorParameters(oscNumber: 1) ?? []
                var oscInfo = "Found \(oscParams.count) oscillator-related parameters:\n"
                for param in oscParams.prefix(10) {
                    oscInfo += "• \(param.displayName): \(String(format: "%.2f", param.value))\n"
                }
                response = oscInfo
            } else if lowerMessage.contains("parameters") {
                if let params = session.getCurrentParameters() {
                    response = "Found \(params.count) parameters. Use search or ask about specific ones!"
                } else {
                    response = "No plugin loaded or no parameters available."
                }
            } else {
                response = "I can show oscillator parameters, all parameters, and more. What would you like to see?"
            }
        } else if lowerMessage.contains("hello") || lowerMessage.contains("hi") || lowerMessage.contains("hey") {
            response = "Hey! I can help you control your synth. Try:\n• \"Set filter cutoff to 2000\"\n• \"Map modwheel to all oscillators\"\n• \"Randomize parameters\"\n• \"Show oscillator levels\""
        } else if lowerMessage.contains("help") {
            response = """
            I can help you control your synth! Here's what I can do:
            
            🎛️ Set Parameters:
            • "Set filter cutoff to 2000"
            • "Set oscillator 1 level to 0.8"
            
            ⌨️ MIDI Mapping:
            • "Map modwheel to all oscillators"
            
            🎲 Randomize:
            • "Randomize parameters"
            
            📊 Get Info:
            • "Show oscillator parameters"
            • "List all parameters"
            
            Just ask me in natural language!
            """
        } else {
            response = "I can help you control your synth! Try:\n• \"Set filter cutoff to 2000\"\n• \"Map modwheel to all oscillators\"\n• \"Randomize parameters\"\n• \"Show oscillator levels\"\n\nOr say \"help\" for more options!"
        }
        
                continuation.resume(returning: jsonResponse(["response": response]))
            }
        }
    }

    private func extractNumbers(from text: String) -> [Double] {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Double($0) }
        
        // Also try to extract numbers with units (Hz, kHz, etc.)
        let regex = try? NSRegularExpression(pattern: "\\d+(?:\\.\\d+)?", options: [])
        let nsString = text as NSString
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        var allNumbers: [Double] = []
        for match in matches {
            if let number = Double(nsString.substring(with: match.range)) {
                allNumbers.append(number)
            }
        }
        
        // Check for kHz
        if text.lowercased().contains("khz") {
            allNumbers = allNumbers.map { $0 * 1000.0 }
        }
        
        return allNumbers.isEmpty ? numbers : allNumbers
    }
    
    private func extractOscillatorNumbers(from text: String) -> [Int] {
        var oscNumbers: [Int] = []
        
        // Check for "all oscillators" or "all osc"
        if text.lowercased().contains("all oscillator") || text.lowercased().contains("all osc") {
            return [1, 2, 3]
        }
        
        // Extract oscillator numbers
        let regex = try? NSRegularExpression(pattern: "oscillator\\s+(\\d+)", options: .caseInsensitive)
        let nsString = text as NSString
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for match in matches {
            if match.numberOfRanges > 1 {
                let oscNum = nsString.substring(with: match.range(at: 1))
                if let num = Int(oscNum) {
                    oscNumbers.append(num)
                }
            }
        }
        
        // Also check for "osc 1", "osc1", etc.
        let oscRegex = try? NSRegularExpression(pattern: "osc\\s*(\\d+)", options: .caseInsensitive)
        let oscMatches = oscRegex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for match in oscMatches {
            if match.numberOfRanges > 1 {
                let oscNum = nsString.substring(with: match.range(at: 1))
                if let num = Int(oscNum) {
                    oscNumbers.append(num)
                }
            }
        }
        
        return oscNumbers.isEmpty ? [1, 2, 3] : oscNumbers
    }
    
    private func getOscillatorLevelId(_ oscNumber: Int) -> String {
        switch oscNumber {
        case 1: return "50797"
        case 2: return "51513"
        case 3: return "52503"
        default: return "50797"
        }
    }
    
    private func setupModwheelModulation(session: PluginHostSession, targetOscillators: [Int]) async -> String {
        guard let analysis = session.analyzedParameters else {
            return "❌ Parameters not analyzed yet. Please wait a moment and try again."
        }
        
        let modMatrixSlots = analysis.modulationMatrixSlots
        let oscLevelIds = analysis.oscillatorLevelIds
        
        if modMatrixSlots.isEmpty {
            return "❌ Couldn't find modulation matrix parameters. \(analysis.pluginName)'s modulation matrix might need to be configured through the plugin UI."
        }
        
        if oscLevelIds.isEmpty {
            return "❌ Couldn't find oscillator level parameters"
        }
        
        // Find oscillator level parameters
        var foundOscParams: [AUParameter] = []
        for oscId in oscLevelIds.prefix(targetOscillators.count) {
            if let param = session.findParameter(identifier: oscId) {
                foundOscParams.append(param)
            }
        }
        
        if foundOscParams.isEmpty {
            return "❌ Couldn't find oscillator level parameters"
        }
        
        var successCount = 0
        var details = ""
        
        // Use mod matrix slots for each oscillator
        for (index, oscParam) in foundOscParams.enumerated() {
            if index < modMatrixSlots.count {
                let slot = modMatrixSlots[index]
                
                // Set source to modwheel
                // Modwheel is typically MIDI CC 1, which might be source index 1 or a specific value
                if let sourceParam = slot.source {
                    // Try setting to modwheel value (varies by plugin)
                    // In Vital/Serum, modwheel might be source index 1
                    sourceParam.setValue(1.0, originator: nil)
                    details += "Slot \(index + 1): Set source to modwheel\n"
                }
                
                // Set destination to oscillator level
                // Find the destination index that corresponds to this oscillator level
                if let destParam = slot.dest {
                    // We need to find the parameter address/index for the oscillator level
                    // This is plugin-specific, but we can try to set it based on the parameter address
                    // For now, we'll set a reasonable value - this might need plugin-specific tuning
                    let destValue = AUValue(oscParam.address) // Use parameter address as destination index
                    destParam.setValue(destValue, originator: nil)
                    details += "Slot \(index + 1): Set destination to osc level (address: \(oscParam.address))\n"
                }
                
                // Set amount
                if let amountParam = slot.amount {
                    amountParam.setValue(1.0, originator: nil)
                    details += "Slot \(index + 1): Set amount to 1.0\n"
                    successCount += 1
                }
            }
        }
        
        if successCount > 0 {
            return "✅ Set up modwheel modulation routing in \(successCount) modulation matrix slot(s)!\n\n\(details)\n⚠️ Note: You may need to verify the source and destination settings in \(analysis.pluginName)'s UI, as modulation matrix parameter indices vary by plugin version."
        } else {
            return "⚠️ Found modulation matrix parameters but couldn't configure them automatically. Please use \(analysis.pluginName)'s modulation matrix UI:\n1. Open the modulation matrix\n2. Set source to Modwheel\n3. Set destination to Oscillator Level\n4. Adjust amount"
        }
    }
    
    /// Full HTTP message as bytes. `Content-Length` must match the exact body byte count (large `get_parameters` JSON).
    private func httpResponseData(status: String, contentType: String, body: Data) -> Data {
        let header =
            "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "\r\n"
        var out = Data(header.utf8)
        out.append(body)
        return out
    }

    private func httpPlainResponse(status: String, body: String) -> Data {
        let b = body.data(using: .utf8) ?? Data()
        return httpResponseData(status: status, contentType: "text/plain; charset=utf-8", body: b)
    }

    private func jsonResponse(_ data: [String: Any]) -> Data {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []) else {
            let err = #"{"error":"Failed to serialize"}"#.data(using: .utf8) ?? Data()
            return httpResponseData(status: "500 Internal Server Error", contentType: "application/json", body: err)
        }
        return httpResponseData(status: "200 OK", contentType: "application/json", body: jsonData)
    }
    
    func stop() {
        isStopped = true
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }
}

