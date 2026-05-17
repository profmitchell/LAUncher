import SwiftUI
import AVFoundation

struct MCPToolView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTool: String = "randomize_parameters"
    @State private var intensity: Double = 0.4
    @State private var preserveCategories: Set<String> = []
    @State private var isLoading = false
    @State private var lastResult: String?
    @State private var showingParameters = false
    @State private var showingMCPServer = false
    @State private var mcpConnectionStatus = "Disconnected"
    @State private var categorizedParameters: [String: [AUParameter]] = [:]
    @State private var selectedOscillator = 1
    @State private var filterCutoffValue: Double = 1000.0
    @State private var showingFilterControl = false
    @State private var commandInput: String = ""
    @State private var parameterNameInput: String = ""
    @State private var parameterValueInput: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MCP Tools")
                    .font(.title2.weight(.medium))
                Text("Control and analyze your plugin")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                toolPicker
                
                if selectedTool == "randomize_parameters" {
                    randomizeControls
                } else if selectedTool == "get_parameters" {
                    parametersView
                } else if selectedTool == "analyze_patch" {
                    analysisView
                } else if selectedTool == "mcp_connection" {
                    mcpConnectionView
                } else if selectedTool == "filter_control" {
                    filterControlView
                } else if selectedTool == "quick_set" {
                    quickSetView
                }
                
                if let result = lastResult {
                    resultView(result)
                }
            }
            .padding()
        }
    }
    
    private var toolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Tool")
                .font(.headline)
            Picker("", selection: $selectedTool) {
                Text("Randomize").tag("randomize_parameters")
                Text("Parameters").tag("get_parameters")
                Text("Filter Ctrl").tag("filter_control")
                Text("Quick Set").tag("quick_set")
                Text("MCP").tag("mcp_connection")
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var randomizeControls: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Intensity: \(Int(intensity * 100))%")
                        .font(.subheadline)
                    Spacer()
                    Text(intensity < 0.3 ? "Subtle" : intensity < 0.7 ? "Moderate" : "Wild")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $intensity, in: 0.0...1.0)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Preserve Categories")
                    .font(.subheadline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    CategoryToggle(title: "Filter", isSelected: preserveCategories.contains("Filter")) {
                        if preserveCategories.contains("Filter") {
                            preserveCategories.remove("Filter")
                        } else {
                            preserveCategories.insert("Filter")
                        }
                    }
                    CategoryToggle(title: "Envelope 1", isSelected: preserveCategories.contains("Envelope 1")) {
                        if preserveCategories.contains("Envelope 1") {
                            preserveCategories.remove("Envelope 1")
                        } else {
                            preserveCategories.insert("Envelope 1")
                        }
                    }
                    CategoryToggle(title: "Oscillator 1", isSelected: preserveCategories.contains("Oscillator 1")) {
                        if preserveCategories.contains("Oscillator 1") {
                            preserveCategories.remove("Oscillator 1")
                        } else {
                            preserveCategories.insert("Oscillator 1")
                        }
                    }
                }
            }
            
            Button {
                randomizeParameters()
            } label: {
                Label("Randomize", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || session.currentComponent == nil)
        }
    }
    
    private var parametersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    showingParameters.toggle()
                    if showingParameters {
                        categorizedParameters = session.getParametersByCategory()
                    }
                } label: {
                    Label(showingParameters ? "Hide Parameters" : "Show Parameters", systemImage: showingParameters ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                
                if showingParameters {
                    Button {
                        categorizedParameters = session.getParametersByCategory()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if showingParameters {
                if categorizedParameters.isEmpty {
                    Text("No parameters available")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(categorizedParameters.keys.sorted()), id: \.self) { category in
                                ParameterCategorySection(title: category, parameters: categorizedParameters[category] ?? [])
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }
            }
        }
    }
    
    private var mcpConnectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MCP Server Status")
                    .font(.headline)
                
                HStack {
                    Circle()
                        .fill(mcpConnectionStatus == "Connected" ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(mcpConnectionStatus)
                        .font(.subheadline)
                }
                
                Text("The Node MCP server talks to LAUncher on port 5555. Run LAUncher with a plugin loaded so tools use live AU data (no mock fallback).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Test: First Oscillator")
                    .font(.headline)
                
                if let oscParams = session.getOscillatorParameters(oscNumber: selectedOscillator) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(oscParams, id: \.identifier) { param in
                            HStack {
                                Text(param.displayName)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(param.value, specifier: "%.3f")")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                } else {
                    Text("No oscillator parameters found")
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Can Cursor AI see your plugin?")
                    .font(.headline)
                
                Text("Yes! I can query the MCP server to see your plugin's parameters. The first oscillator has:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Wave (osc1_wave): 0-10")
                    Text("• Detune (osc1_detune): -1 to 1")
                    Text("• Voices (osc1_voices): 1-16")
                    Text("• Stereo Width (osc1_stereoWidth): 0-1")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
    
    private var quickSetView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Parameter Set")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Set any parameter by name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parameter Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("e.g., cutoff, filter_cutoff, Filter Cutoff", text: $parameterNameInput)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("e.g., 5000", text: $parameterValueInput)
                        .textFieldStyle(.roundedBorder)
                }
                
                Button {
                    setParameterByName()
                } label: {
                    Label("Set Parameter", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(parameterNameInput.isEmpty || parameterValueInput.isEmpty || session.currentComponent == nil)
            }
            
            if let result = lastResult, selectedTool == "quick_set" {
                resultView(result)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Examples")
                    .font(.subheadline.weight(.medium))
                
                VStack(alignment: .leading, spacing: 4) {
                    ExampleButton(session: session, name: "cutoff", value: "5000") {
                        parameterNameInput = "cutoff"
                        parameterValueInput = "5000"
                    }
                    ExampleButton(session: session, name: "env1_attack", value: "0.1") {
                        parameterNameInput = "env1_attack"
                        parameterValueInput = "0.1"
                    }
                    ExampleButton(session: session, name: "osc1_wave", value: "3") {
                        parameterNameInput = "osc1_wave"
                        parameterValueInput = "3"
                    }
                }
            }
        }
        .padding()
    }
    
    private func setParameterByName() {
        guard let value = Double(parameterValueInput) else {
            lastResult = "❌ Invalid value: \(parameterValueInput)"
            return
        }
        
        let success = session.setParameterValue(displayName: parameterNameInput, value: value)
        
        if success {
            lastResult = "✅ Set \(parameterNameInput) = \(value)"
        } else {
            lastResult = "❌ Parameter not found: \(parameterNameInput)"
        }
    }
    
    private var filterControlView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let filterParam = session.getFilterCutoff() {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filter Cutoff")
                        .font(.headline)
                    
                    HStack {
                        Text("Current: \(filterParam.value, specifier: "%.1f") Hz")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Text("Range: \(filterParam.minValue, specifier: "%.0f") - \(filterParam.maxValue, specifier: "%.0f") Hz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(filterParam.value) },
                            set: { newValue in
                                filterCutoffValue = newValue
                                _ = session.setParameterValue(displayName: "cutoff", value: newValue)
                            }
                        ),
                        in: Double(filterParam.minValue)...Double(filterParam.maxValue)
                    )
                    
                    HStack(spacing: 12) {
                        Button("100 Hz") {
                            _ = session.setParameterValue(displayName: "cutoff", value: 100)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("500 Hz") {
                            _ = session.setParameterValue(displayName: "cutoff", value: 500)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("1 kHz") {
                            _ = session.setParameterValue(displayName: "cutoff", value: 1000)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("5 kHz") {
                            _ = session.setParameterValue(displayName: "cutoff", value: 5000)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("10 kHz") {
                            _ = session.setParameterValue(displayName: "cutoff", value: 10000)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    Text("Filter Cutoff Not Found")
                        .font(.headline)
                    Text("No filter cutoff parameter detected in this plugin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Refresh Parameters") {
                        categorizedParameters = session.getParametersByCategory()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }
    
    private var analysisView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                analyzePatch()
            } label: {
                Label("Analyze Current Patch", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || session.currentComponent == nil)
        }
    }
    
    private func resultView(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Result")
                .font(.headline)
            Text(result)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        }
    }
    
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func randomizeParameters() {
        guard session.currentComponent != nil else { return }
        
        isLoading = true
        
        Task {
            do {
                let categories = Array(preserveCategories)
                let result = try await session.randomizeParameters(intensity: intensity, preserveCategories: categories)
                
                await MainActor.run {
                    lastResult = "✅ Randomized \(result.randomizedCount) parameters with \(Int(result.intensity * 100))% intensity"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    lastResult = "❌ Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func analyzePatch() {
        isLoading = true
        
        Task {
            do {
                let analysis = try await session.analyzePatch()
                
                await MainActor.run {
                    lastResult = """
                    📊 Analysis:
                    
                    \(analysis.summary)
                    
                    Timbre:
                    • Brightness: \(Int(analysis.timbre.brightness * 100))%
                    • Warmth: \(Int(analysis.timbre.warmth * 100))%
                    • Roughness: \(Int(analysis.timbre.roughness * 100))%
                    • Space: \(Int(analysis.timbre.space * 100))%
                    """
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    lastResult = "❌ Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct CategoryToggle: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct ParameterRow: View {
    let param: AUParameter
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(param.displayName)
                    .font(.subheadline.weight(.medium))
                Text(param.identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(param.value, specifier: "%.2f")")
                    .font(.subheadline.monospacedDigit())
                Text("\(param.minValue, specifier: "%.1f") - \(param.maxValue, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ParameterCategorySection: View {
    let title: String
    let parameters: [AUParameter]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            ForEach(parameters, id: \.identifier) { param in
                ParameterRow(param: param)
                    .padding(.leading, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct ExampleButton: View {
    let session: PluginHostSession
    let name: String
    let value: String
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            action()
            if let doubleValue = Double(value) {
                _ = session.setParameterValue(displayName: name, value: doubleValue)
            }
        }) {
            HStack {
                Text("\(name) = \(value)")
                    .font(.caption.monospaced())
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

