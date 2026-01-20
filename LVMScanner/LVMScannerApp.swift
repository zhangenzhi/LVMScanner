import SwiftUI
import ScreenCaptureKit

@main
struct LVMScannerApp: App {
    @StateObject private var captureService = CaptureService()
    
    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environmentObject(captureService)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - 主容器

struct MainContainerView: View {
    @EnvironmentObject var captureService: CaptureService
    @State private var selectedSessionID: UUID?
    @State private var isShowingAddSourceSheet = false
    
    var body: some View {
        NavigationSplitView {
            SidebarListView(selection: $selectedSessionID, showAddSheet: $isShowingAddSourceSheet)
        } detail: {
            if let sessionID = selectedSessionID,
               let session = captureService.activeSessions.first(where: { $0.id == sessionID }) {
                SessionDetailLayout(session: session)
            } else {
                EmptyStateView(showAddSheet: $isShowingAddSourceSheet)
            }
        }
        .sheet(isPresented: $isShowingAddSourceSheet) {
            AddSourceSheet(isPresented: $isShowingAddSourceSheet)
        }
    }
}

// MARK: - 第一列：导航侧边栏

struct SidebarListView: View {
    @EnvironmentObject var captureService: CaptureService
    @Binding var selection: UUID?
    @Binding var showAddSheet: Bool
    
    var body: some View {
        List(selection: $selection) {
            Section(header: Text("正在采集 (Active)")) {
                ForEach(captureService.activeSessions) { session in
                    HStack {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                        VStack(alignment: .leading) {
                            Text(session.source.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(session.source.appName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("停止采集", role: .destructive) {
                            captureService.removeSession(session)
                            if selection == session.id { selection = nil }
                        }
                    }
                }
            }
        }
        .navigationTitle("LVM 控制台")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Label("添加源", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - 核心内容布局 (第二列 + 第三列)

struct SessionDetailLayout: View {
    @ObservedObject var session: CaptureSession
    @EnvironmentObject var captureService: CaptureService
    
    var body: some View {
        GeometryReader { geo in
            HSplitView {
                // --- 第二列：监控与信息流 ---
                VSplitView {
                    ZStack {
                        Color.black
                        if let img = session.lastCapturedImage {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "eye.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("等待画面...")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        VStack {
                            HStack {
                                Spacer()
                                Label("LIVE", systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.red.opacity(0.8))
                                    .cornerRadius(4)
                            }
                            Spacer()
                        }
                        .padding()
                    }
                    .frame(minHeight: 200)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("实时提取数据流 (Data Stream)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            Spacer()
                        }
                        
                        List(session.analyzer.logs) { log in
                            HStack(alignment: .top) {
                                Text(log.timestamp, style: .time)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(log.content)
                                    .font(.caption)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .frame(minHeight: 150)
                }
                .frame(minWidth: 400)
                
                // --- 第三列：LLM 交互窗口 ---
                ChatInteractionView(session: session)
                    .frame(minWidth: 300)
            }
        }
        .onAppear {
            startCaptureLoop()
        }
    }
    
    func startCaptureLoop() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                if let image = await captureService.captureFrame(for: session.source.id) {
                    await MainActor.run {
                        session.lastCapturedImage = image
                    }
                    await session.analyzer.analyzeFrame(image: image)
                }
            }
        }
    }
}

// MARK: - 第三列具体实现：聊天窗口

struct ChatInteractionView: View {
    @ObservedObject var session: CaptureSession
    @State private var inputText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI 助手")
                    .font(.headline)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
            .padding()
            .background(.regularMaterial)
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.analyzer.chatHistory) { msg in
                            ChatBubble(message: msg)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.analyzer.chatHistory.count) { _ in
                    if let lastId = session.analyzer.chatHistory.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
            
            Divider()
            
            HStack {
                TextField("询问关于画面的问题...", text: $inputText)
                    .textFieldStyle(.plain)
                    .onSubmit(sendMessage)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.isEmpty || session.analyzer.isAnalyzing)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    func sendMessage() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        Task {
            await session.analyzer.sendMessage(text, contextImage: session.lastCapturedImage)
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
                Text(message.text)
                    .padding(10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            } else {
                VStack(alignment: .leading) {
                    Text(message.text)
                        .padding(10)
                        .background(Color(nsColor: .controlColor))
                        .cornerRadius(12)
                }
                Spacer()
            }
        }
    }
}

// MARK: - 辅助视图：添加源 Sheet

struct AddSourceSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var captureService: CaptureService
    @State private var isLoading = true
    
    var body: some View {
        VStack {
            Text("选择采集源")
                .font(.headline)
                .padding()
            
            if isLoading {
                ProgressView("正在扫描窗口...")
            } else {
                List(captureService.availableWindows, id: \.self) { window in
                    HStack {
                        Image(systemName: "macwindow")
                        VStack(alignment: .leading) {
                            Text(window.name).bold()
                            Text(window.appName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("添加") {
                            captureService.addSession(for: window)
                            isPresented = false
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            Task {
                await captureService.fetchAvailableWindows()
                isLoading = false
            }
        }
    }
}

struct EmptyStateView: View {
    @Binding var showAddSheet: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("暂无活跃采集")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("添加采集源") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
