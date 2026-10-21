import SwiftUI
import AVFoundation

/// Plugin library only — search, filter, list. No tools clutter.
struct LeftSidebarView: View {
    @ObservedObject var session: PluginHostSession
    @State private var pluginSearchText = ""
    @State private var selectedScope: SidebarPluginScope = .all
    @State private var loadingComponent: AVAudioUnitComponent?
    @State private var didApplyDefaultScope = false

    private enum SidebarPluginScope: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case instruments = "Inst"
        case effects = "FX"

        var id: String { rawValue }
    }

    private var pluginSource: [AVAudioUnitComponent] {
        let components = session.availablePlugins
        switch selectedScope {
        case .all:
            return components
        case .recent:
            return session.recentPluginComponents
        case .instruments:
            return components.filter { $0.audioComponentDescription.componentType == kAudioUnitType_MusicDevice }
        case .effects:
            return components.filter {
                let t = $0.audioComponentDescription.componentType
                return t == kAudioUnitType_Effect || t == kAudioUnitType_MusicEffect
            }
        }
    }

    private var filteredPlugins: [AVAudioUnitComponent] {
        let sorted = pluginSource.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !pluginSearchText.isEmpty else { return sorted }
        return sorted.filter { component in
            component.name.localizedCaseInsensitiveContains(pluginSearchText) ||
            component.manufacturerName.localizedCaseInsensitiveContains(pluginSearchText)
        }
    }

    private var theme: AppTheme {
        session.themeManager.currentTheme
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            searchAndFilters
            pluginList
        }
        .background(LauncherChrome.panel(theme))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(LauncherChrome.border(theme).opacity(0.5))
                .frame(width: 1)
        }
        .onAppear {
            guard !didApplyDefaultScope else { return }
            didApplyDefaultScope = true
            if !session.recentPlugins.isEmpty {
                selectedScope = .recent
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LauncherChrome.textMain(theme))
            Spacer()
            Button {
                session.rescanPlugins()
            } label: {
                if session.isRescanning {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(LauncherChrome.textMuted(theme))
            .disabled(session.isRescanning)
            .help("Rescan Audio Units")

            Button {
                session.refreshPluginList()
                session.isShowingPluginPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(LauncherChrome.textMuted(theme))
            .help("Browse all plugins")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LauncherChrome.textMuted(theme))
                TextField("Search", text: $pluginSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Picker("Type", selection: $selectedScope) {
                ForEach(SidebarPluginScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            if !session.lastScanSummary.isEmpty {
                Text(session.isRescanning ? "Rescanning…" : session.lastScanSummary)
                    .font(.caption2)
                    .foregroundStyle(LauncherChrome.textMuted(theme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var pluginList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if filteredPlugins.isEmpty {
                    Text(pluginSearchText.isEmpty ? "No plugins in this filter." : "No matches.")
                        .font(.caption)
                        .foregroundStyle(LauncherChrome.textMuted(theme))
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(filteredPlugins, id: \.self) { component in
                        SidebarPluginRow(
                            component: component,
                            isCurrent: session.currentComponent == component,
                            isLoading: loadingComponent == component,
                            typeLabel: componentTypeLabel(component),
                            theme: theme
                        ) {
                            load(component)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private func load(_ component: AVAudioUnitComponent) {
        guard loadingComponent == nil, session.currentComponent != component else { return }
        loadingComponent = component
        Task { @MainActor in
            defer { loadingComponent = nil }
            await session.load(component: component)
        }
    }

    private func componentTypeLabel(_ component: AVAudioUnitComponent) -> String {
        switch component.audioComponentDescription.componentType {
        case kAudioUnitType_MusicDevice: return "Instrument"
        case kAudioUnitType_MusicEffect: return "Music FX"
        case kAudioUnitType_Effect: return "Effect"
        case kAudioUnitType_Generator: return "Generator"
        default: return component.typeName
        }
    }
}

private struct SidebarPluginRow: View {
    let component: AVAudioUnitComponent
    let isCurrent: Bool
    let isLoading: Bool
    let typeLabel: String
    let theme: AppTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                pluginIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.name)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(LauncherChrome.textMain(theme))
                        .lineLimit(1)
                    Text("\(component.manufacturerName) · \(typeLabel)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(LauncherChrome.textMuted(theme))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if isCurrent {
                    Circle()
                        .fill(LauncherChrome.accent(theme))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? LauncherChrome.accent(theme).opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var pluginIcon: some View {
        if let nsImage = component.icon {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(LauncherChrome.textMuted(theme))
                )
        }
    }
}
