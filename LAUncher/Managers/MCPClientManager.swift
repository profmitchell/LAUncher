import Foundation
import Combine

// MCP Parameter Models
struct MCPParameter: Codable, Identifiable {
    let id: String
    let path: String
    let address: UInt64
    let displayName: String
    let min: Double
    let max: Double
    let unit: String
    var value: Double
}

struct MCPParameterChange: Codable {
    let id: String
    let value: Double
}

struct MCPGetParametersResponse: Codable {
    let plugin: String
    let parameters: [MCPParameter]
}

struct MCPSetParametersResponse: Codable {
    let result: String
    let applied: [MCPParameterChange]
}

struct MCPRandomizeResponse: Codable {
    let result: String
    let applied: [MCPParameterChange]
    let intensity: Double
    let randomizedCount: Int
}

struct MCPPatchSnapshot: Codable {
    let plugin: String
    let name: String
    let categoryGuess: String
    let snapshotId: String
    let oscillators: [MCPSnapshotOscillator]?
    let filter: MCPSnapshotFilter?
    let ampEnv: MCPSnapshotAmpEnv?
    let modulationOverview: MCPSnapshotModulation?
    let rawParameters: [MCPParameter]?
}

struct MCPSnapshotOscillator: Codable {
    let index: Int
    let wave: String
    let voices: Int
    let detune: Double
    let stereoWidth: Double
}

struct MCPSnapshotFilter: Codable {
    let type: String
    let cutoffHz: Double
    let resonance: Double
    let drive: Double
}

struct MCPSnapshotAmpEnv: Codable {
    let attackMs: Double
    let decayMs: Double
    let sustain: Double
    let releaseMs: Double
}

struct MCPSnapshotModulation: Codable {
    let sidechainLFOs: Int
    let envelopesUsed: Int
    let macrosUsed: Int
}

struct MCPAnalysis: Codable {
    let summary: String
    let timbre: MCPTimbre
    let coreIngredients: [String]
    let usageNotes: [String]
}

struct MCPTimbre: Codable {
    let brightness: Double
    let warmth: Double
    let roughness: Double
    let space: Double
}

struct MCPExplanation: Codable {
    let id: String
    let label: String
    let description: String
}

struct MCPExplainResponse: Codable {
    let explanations: [MCPExplanation]
}

// MCP Client Manager
@MainActor
final class MCPClientManager: ObservableObject {
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var availableTools: [String] = []
    
    private var process: Process?
    private var requestId: Int = 0
    
    init() {
        // Initialize but don't connect yet
    }
    
    func connect() async throws {
        let scriptPath = "/Users/Shared/CohenConcepts/LAUncher/LAUncher/dev/mcp/launcher-server.js"
        
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw MCPError.serverNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", scriptPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = pipe
        
        self.process = process
        
        try process.run()
        isConnected = true
        
        // Get available tools
        try await getAvailableTools()
    }
    
    private func getAvailableTools() async throws {
        let response = try await callMethod("tools/list", arguments: nil)
        if let tools = response["tools"] as? [[String: Any]] {
            availableTools = tools.compactMap { $0["name"] as? String }
        }
    }
    
    private func callMethod(_ method: String, arguments: [String: Any]?) async throws -> [String: Any] {
        guard let process = process else {
            throw MCPError.notConnected
        }
        
        requestId += 1
        
        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method
        ]
        
        if let args = arguments {
            request["params"] = args
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw MCPError.invalidRequest
        }
        
        // Note: This is a simplified implementation
        // In a real implementation, you'd need to properly handle async stdout/stdin
        // For now, we'll use a direct approach with the actual plugin data
        
        throw MCPError.notImplemented
    }
    
    func getParameters(filter: [String: Any]? = nil) async throws -> MCPGetParametersResponse {
        // For now, get parameters from the actual plugin
        // This will be replaced with actual MCP call later
        throw MCPError.notImplemented
    }
    
    func setParameters(changes: [MCPParameterChange]) async throws -> MCPSetParametersResponse {
        // For now, set parameters directly on the plugin
        throw MCPError.notImplemented
    }
    
    func randomizeParameters(intensity: Double = 0.4, preserveCategories: [String] = [], excludeIds: [String] = []) async throws -> MCPRandomizeResponse {
        // For now, randomize directly on the plugin
        throw MCPError.notImplemented
    }
}

enum MCPError: LocalizedError {
    case serverNotFound
    case notConnected
    case invalidRequest
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            return "MCP server not found"
        case .notConnected:
            return "Not connected to MCP server"
        case .invalidRequest:
            return "Invalid request format"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}

