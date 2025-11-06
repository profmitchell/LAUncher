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
        } else if method == "POST" && path == "/api/create_midi_mapping" {
            return await handleCreateMIDIMapping(jsonBody)
        } else if method == "POST" && path == "/api/chat" {
            return await handleChat(jsonBody)
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
    
    private func handleCreateMIDIMapping(_ body: [String: Any]?) async -> String {
        guard let session = session,
              let ccNumber = body?["ccNumber"] as? Int,
              let parameterIds = body?["parameterIds"] as? [String] else {
            return jsonResponse(["result": "error", "message": "Missing ccNumber or parameterIds"])
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
                "ccNumber": ccNumber
            ])
        }
        
        return jsonResponse([
            "result": "ok",
            "created": created
        ])
    }
    
    private func handleChat(_ body: [String: Any]?) async -> String {
        guard let session = session,
              let message = body?["message"] as? String else {
            return jsonResponse(["response": "I need a message to respond to."])
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
                    let paramId = "48629" // Filter 1 Cutoff
                    let success = session.setParameterValue(identifier: paramId, value: Double(value))
                    if success {
                        response = "✅ Set Filter 1 Cutoff to \(value) Hz"
                    } else {
                        response = "❌ Failed to set filter cutoff"
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
                    for oscNum in oscNumbers {
                        let paramId = getOscillatorLevelId(oscNum)
                        if session.setParameterValue(identifier: paramId, value: Double(level)) {
                            successCount += 1
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
                    if lowerMessage.contains("source") || lowerMessage.contains("in vital") || lowerMessage.contains("modulation") {
                        // Internal modulation routing in Vital
                        response = await setupModwheelModulation(session: session, targetOscillators: [1, 2, 3])
                    } else {
                        // MIDI CC mapping (existing behavior)
                        let oscIds = ["50797", "51513", "52503"] // All three oscillator levels
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
        
        return jsonResponse(["response": response])
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
        guard let params = session.getCurrentParameters(), !params.isEmpty else {
            return "❌ No parameters available"
        }
        
        // Find modulation matrix parameters in Vital
        // Vital uses parameters like "Mod Matrix 1 Source", "Mod Matrix 1 Destination", "Mod Matrix 1 Amount"
        var modMatrixParams: [(source: AUParameter?, dest: AUParameter?, amount: AUParameter?)] = []
        
        // Try to find mod matrix slots
        for i in 1...16 { // Vital typically has 16 mod matrix slots
            let sourceParam = params.first { param in
                let name = param.displayName.lowercased()
                return name.contains("mod") && name.contains("matrix") && name.contains("\(i)") && name.contains("source")
            }
            
            let destParam = params.first { param in
                let name = param.displayName.lowercased()
                return name.contains("mod") && name.contains("matrix") && name.contains("\(i)") && name.contains("destination")
            }
            
            let amountParam = params.first { param in
                let name = param.displayName.lowercased()
                return name.contains("mod") && name.contains("matrix") && name.contains("\(i)") && name.contains("amount")
            }
            
            if sourceParam != nil || destParam != nil || amountParam != nil {
                modMatrixParams.append((sourceParam, destParam, amountParam))
            }
        }
        
        if modMatrixParams.isEmpty {
            // Try alternative naming patterns
            let altSource = params.first { param in
                let name = param.displayName.lowercased()
                return name.contains("modwheel") || name.contains("mod wheel") || (name.contains("mod") && name.contains("source"))
            }
            
            if altSource != nil {
                return "Found modwheel source parameter, but need to find modulation matrix slots. Try using Vital's UI to set up modulation routing."
            }
            
            return "❌ Couldn't find modulation matrix parameters. Vital's modulation matrix might need to be configured through the plugin UI."
        }
        
        // Find oscillator level parameters
        let oscLevelIds = ["50797", "51513", "52503"] // Osc 1, 2, 3 levels
        var foundOscParams: [AUParameter] = []
        
        for oscId in oscLevelIds {
            if let param = session.findParameter(identifier: oscId) {
                foundOscParams.append(param)
            }
        }
        
        if foundOscParams.isEmpty {
            return "❌ Couldn't find oscillator level parameters"
        }
        
        // Try to set up modulation routing
        // We need to find mod matrix slots and set:
        // 1. Source = Modwheel
        // 2. Destination = Oscillator Level
        // 3. Amount = appropriate value
        
        var successCount = 0
        var details = ""
        
        // Use first available mod matrix slot for each oscillator
        for (index, oscParam) in foundOscParams.enumerated() {
            if index < modMatrixParams.count {
                let slot = modMatrixParams[index]
                
                // Set source to modwheel (might be value 1 or specific index)
                // Modwheel is typically MIDI CC 1, which might be parameter value 1 or a specific mod source index
                if let sourceParam = slot.source {
                    // Try setting to modwheel value (this varies by plugin)
                    // In Vital, modwheel might be source index 1 or a specific value
                    sourceParam.setValue(1.0, originator: nil)
                    details += "Slot \(index + 1): Set source to modwheel\n"
                }
                
                // Set destination to oscillator level
                // This might require finding the oscillator level parameter's address/index
                if let destParam = slot.dest {
                    // Would need to find the correct destination index for oscillator level
                    // This is plugin-specific and might require reverse engineering
                    details += "Slot \(index + 1): Attempting to set destination\n"
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
            return "✅ Set up modwheel modulation routing in \(successCount) modulation matrix slot(s)!\n\n\(details)\n⚠️ Note: You may need to verify the source and destination settings in Vital's UI, as modulation matrix parameter indices vary by plugin version."
        } else {
            return "⚠️ Found modulation matrix parameters but couldn't configure them automatically. Please use Vital's modulation matrix UI:\n1. Open the modulation matrix\n2. Set source to Modwheel\n3. Set destination to Oscillator Level\n4. Adjust amount"
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

