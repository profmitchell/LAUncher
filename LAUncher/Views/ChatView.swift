import SwiftUI
import AVFoundation
import AppKit

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}

struct ChatView: View {
    @ObservedObject var session: PluginHostSession
    let window: NSWindow
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            Divider()
            inputArea
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Chat")
                    .font(.title2.weight(.medium))
                Text("Control your synth with natural language")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                window.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Start a conversation")
                                .font(.headline)
                            Text("Try: \"Set filter cutoff to 2000 Hz\" or \"Map modwheel to all oscillators\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(isLoading)
                .onSubmit {
                    sendMessage()
                }
            
            Button {
                sendMessage()
            } label: {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.large)
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding()
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(text: text, isUser: true, timestamp: Date())
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        
        // Send to API
        Task {
            do {
                let response = try await session.sendChatMessage(text)
                await MainActor.run {
                    let aiMessage = ChatMessage(text: response, isUser: false, timestamp: Date())
                    messages.append(aiMessage)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(text: "Error: \(error.localizedDescription)", isUser: false, timestamp: Date())
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isUser ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .cornerRadius(12)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 500, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

