import SwiftUI
import AVFoundation

struct PluginPickerView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var loadingComponent: AVAudioUnitComponent?
    @State private var errorMessage: String?

    private var filteredComponents: [AVAudioUnitComponent] {
        let components = session.availablePlugins.isEmpty ? session.availableInstruments : session.availablePlugins
        guard !searchText.isEmpty else { return components }
        return components.filter { component in
            component.name.localizedCaseInsensitiveContains(searchText) ||
            component.manufacturerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            pluginList
            if let errorMessage {
                Divider()
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Load Audio Unit Plugin")
                    .font(.title2.weight(.medium))
                Text("Pick any installed AU or AUv3 plugin to host")
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

    private var searchField: some View {
        TextField("Search instruments…", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding()
    }

    private var pluginList: some View {
        List {
            if filteredComponents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No matching plugins found.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
            } else {
                ForEach(filteredComponents, id: \.self) { component in
                    Button {
                        load(component)
                    } label: {
                        HStack(spacing: 16) {
                            if let icon = component.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "waveform.path")
                                            .foregroundStyle(.secondary)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name)
                                    .font(.headline)
                                Text(component.manufacturerName)
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            Spacer()
                            if loadingComponent == component {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }

    private func load(_ component: AVAudioUnitComponent) {
        guard loadingComponent == nil else { return }
        loadingComponent = component
        errorMessage = nil

        Task { @MainActor in
            defer { loadingComponent = nil }
            await session.load(component: component)
            if session.currentComponent == component {
                dismiss()
            } else if let error = session.lastErrorDescription {
                errorMessage = error
            }
        }
    }
}
