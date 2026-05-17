import SwiftUI
import AVFoundation

struct PluginPickerView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedScope: PluginScope = .all
    @State private var loadingComponent: AVAudioUnitComponent?
    @State private var errorMessage: String?

    private enum PluginScope: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case instruments = "Instruments"
        case effects = "Effects"
        case generators = "Generators"

        var id: String { rawValue }
    }

    private var baseComponents: [AVAudioUnitComponent] {
        let components = session.availablePlugins.isEmpty ? session.availableInstruments : session.availablePlugins
        switch selectedScope {
        case .all:
            return components
        case .recent:
            return session.recentPluginComponents
        case .instruments:
            return components.filter { $0.audioComponentDescription.componentType == kAudioUnitType_MusicDevice }
        case .effects:
            return components.filter { $0.audioComponentDescription.componentType == kAudioUnitType_Effect }
        case .generators:
            return components.filter { $0.audioComponentDescription.componentType == kAudioUnitType_Generator }
        }
    }

    private var filteredComponents: [AVAudioUnitComponent] {
        guard !searchText.isEmpty else { return baseComponents }
        return baseComponents.filter { component in
            component.name.localizedCaseInsensitiveContains(searchText) ||
            component.manufacturerName.localizedCaseInsensitiveContains(searchText) ||
            component.typeName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedComponents: [(manufacturer: String, components: [AVAudioUnitComponent])] {
        Dictionary(grouping: filteredComponents, by: \.manufacturerName)
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.manufacturer.localizedCaseInsensitiveCompare($1.manufacturer) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            windowHeader
            Divider()

            HSplitView {
                sidebar
                    .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)

                pluginList
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 880, height: 640)
        .background(.thinMaterial)
    }

    private var windowHeader: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Load Audio Unit")
                        .font(.title2.weight(.semibold))
                    Text("\(filteredComponents.count) available in \(selectedScope.rawValue.lowercased())")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    session.rescanPlugins()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }

                Button("Close") {
                    dismiss()
                }
            }

            HStack(spacing: 12) {
                TextField("Search plugins, makers, or types", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $selectedScope) {
                    ForEach(PluginScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
            }
        }
        .padding()
    }

    private var sidebar: some View {
        List {
            Section("Browse") {
                ForEach(PluginScope.allCases) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        Label(scope.rawValue, systemImage: icon(for: scope))
                    }
                    .buttonStyle(.plain)
                    .fontWeight(selectedScope == scope ? .semibold : .regular)
                }
            }

            if !session.recentPlugins.isEmpty {
                Section("Recently Loaded") {
                    ForEach(session.recentPlugins.prefix(8)) { recent in
                        Button {
                            Task { @MainActor in
                                await session.loadRecentPlugin(recent)
                                if session.currentComponent?.name == recent.name {
                                    dismiss()
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recent.name)
                                    .lineLimit(1)
                                Text(recent.manufacturerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Clear Recent", role: .destructive) {
                        session.clearRecentPlugins()
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var pluginList: some View {
        VStack(spacing: 0) {
            if filteredComponents.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedComponents, id: \.manufacturer) { group in
                        Section(group.manufacturer) {
                            ForEach(group.components, id: \.self) { component in
                                Button {
                                    load(component)
                                } label: {
                                    PluginRow(
                                        component: component,
                                        isLoading: loadingComponent == component,
                                        typeLabel: componentTypeLabel(component)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if let errorMessage {
                Divider()
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Plugins Found", systemImage: "magnifyingglass")
        } description: {
            Text(searchText.isEmpty ? "Try rescanning your installed Audio Units." : "No installed Audio Unit matches your search.")
        } actions: {
            Button("Rescan Plugins") {
                session.rescanPlugins()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func icon(for scope: PluginScope) -> String {
        switch scope {
        case .all: return "square.grid.2x2"
        case .recent: return "clock"
        case .instruments: return "pianokeys"
        case .effects: return "slider.horizontal.3"
        case .generators: return "waveform"
        }
    }

    private func componentTypeLabel(_ component: AVAudioUnitComponent) -> String {
        switch component.audioComponentDescription.componentType {
        case kAudioUnitType_MusicDevice: return "Instrument"
        case kAudioUnitType_Effect: return "Effect"
        case kAudioUnitType_Generator: return "Generator"
        case kAudioUnitType_Mixer: return "Mixer"
        case kAudioUnitType_Panner: return "Panner"
        case kAudioUnitType_FormatConverter: return "Format"
        case kAudioUnitType_OfflineEffect: return "Offline"
        default: return component.typeName
        }
    }
}

private struct PluginRow: View {
    let component: AVAudioUnitComponent
    let isLoading: Bool
    let typeLabel: String

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                Text(component.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(component.manufacturerName)
                    Text(typeLabel)
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .lineLimit(1)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.turn.down.left")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let icon = component.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.secondary)
                )
        }
    }
}
