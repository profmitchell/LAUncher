import SwiftUI
import AppKit
import AVFAudio
import UniformTypeIdentifiers

struct ParameterExportView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss
    @State private var hasCopied = false
    @State private var hasSaved = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            jsonContent
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plugin Parameters Export")
                    .font(.title2.weight(.medium))
                if let component = session.currentComponent {
                    Text("\(component.name) by \(component.manufacturerName)")
                        .foregroundStyle(.secondary)
                }
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
    
    private var jsonContent: some View {
        ScrollView {
            Text(session.exportedParameterJSON)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private var footer: some View {
        HStack {
            Button {
                copyToClipboard()
            } label: {
                Label(hasCopied ? "Copied!" : "Copy to Clipboard", systemImage: hasCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            
            Button {
                saveToFile()
            } label: {
                Label(hasSaved ? "Saved to Desktop!" : "Save to Desktop", systemImage: hasSaved ? "checkmark" : "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            
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
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.exportedParameterJSON, forType: .string)
        hasCopied = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            hasCopied = false
        }
    }
    
    private func saveToFile() {
        // Save directly to desktop
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            print("Failed to get desktop directory")
            return
        }
        
        let fileName = session.currentComponent?.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_") ?? "plugin_parameters"
        let fileURL = desktopURL.appendingPathComponent("\(fileName)_parameters.json")
        
        let jsonData = session.exportedParameterJSON.data(using: .utf8)
        guard let data = jsonData else {
            print("Failed to convert JSON to data")
            return
        }
        
        do {
            try data.write(to: fileURL, options: .atomic)
            print("✅ Saved to: \(fileURL.path)")
            // Show success message
            hasSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                hasSaved = false
            }
        } catch {
            print("Failed to save file: \(error)")
            print("Attempted path: \(fileURL.path)")
        }
    }
}

