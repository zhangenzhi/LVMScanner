import SwiftUI
import Combine

// MARK: - Models

struct AnalysisLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let content: String // 提取出的结构化信息
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let timestamp = Date()
    
    enum MessageRole {
        case user
        case system // LLM
    }
}

// MARK: - Analyzer

@MainActor
class LVMAnalyzer: ObservableObject {
    // 第二列下方：提取的信息流（结构化数据）
    @Published var logs: [AnalysisLog] = []
    
    // 第三列：对话历史
    @Published var chatHistory: [ChatMessage] = []
    
    @Published var isAnalyzing: Bool = false
    
    init() {}
    
    // 模拟 LVM 视觉分析（用于提取信息流）
    func analyzeFrame(image: NSImage) async {
        self.isAnalyzing = true
        
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // 模拟：随机生成一些视觉提取数据
        let findings = [
            "检测到用户正在编辑 SwiftUI 代码，第 20 行存在警告。",
            "画面变化率：低。主要内容为静态文本。",
            "识别到红色按钮控件，位置 (200, 350)。",
            "检测到视频播放，当前无字幕。"
        ]
        
        let content = findings.randomElement() ?? "分析中..."
        let newLog = AnalysisLog(timestamp: Date(), content: content)
        
        self.logs.insert(newLog, at: 0)
        self.isAnalyzing = false
    }
    
    // 模拟 LVM 对话交互（用于第三列 Chat）
    func sendMessage(_ text: String, contextImage: NSImage?) async {
        guard !text.isEmpty else { return }
        
        let userMsg = ChatMessage(role: .user, text: text)
        self.chatHistory.append(userMsg)
        self.isAnalyzing = true
        
        // 模拟思考
        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        
        let responseText = "我看到了你提供的画面。针对你的问题“\(text)”，建议检查一下视图层级结构，或者尝试使用 NavigationSplitView 来优化布局。"
        
        let systemMsg = ChatMessage(role: .system, text: responseText)
        self.chatHistory.append(systemMsg)
        self.isAnalyzing = false
    }
}
