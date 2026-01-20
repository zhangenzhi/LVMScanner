import SwiftUI
import ScreenCaptureKit
import Combine
import OSLog

// MARK: - Models

struct WindowSource: Identifiable, Hashable {
    let id: Int
    let name: String
    let appName: String
}

// MARK: - Session Model

@MainActor
class CaptureSession: Identifiable, ObservableObject, Hashable {
    let id = UUID()
    let source: WindowSource
    
    // 每个会话都有自己独立的分析器实例
    @Published var analyzer = LVMAnalyzer()
    
    // 最后一次捕获的图像
    @Published var lastCapturedImage: NSImage?
    
    init(source: WindowSource) {
        self.source = source
    }
    
    // Hashable / Equatable conformance
    static func == (lhs: CaptureSession, rhs: CaptureSession) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Capture Service

@MainActor
class CaptureService: ObservableObject {
    // 用户已添加到“监控台”的活跃源
    @Published var activeSessions: [CaptureSession] = []
    // 系统中所有可用的窗口（仅在添加时刷新）
    @Published var availableWindows: [WindowSource] = []
    
    private let logger = Logger(subsystem: "com.lvm.app", category: "Capture")
    
    init() {}
    
    // 获取当前系统所有窗口（用于选择器）
    func fetchAvailableWindows() async {
        do {
            let content = try await SCShareableContent.current
            
            let windows = content.windows
                .filter { $0.isOnScreen && $0.title != nil }
                .map { scWindow in
                    WindowSource(
                        id: Int(scWindow.windowID),
                        name: scWindow.title ?? "未知窗口",
                        appName: scWindow.owningApplication?.applicationName ?? "未知应用"
                    )
                }
            self.availableWindows = windows
        } catch {
            logger.error("无法刷新窗口列表: \(error.localizedDescription)")
        }
    }
    
    // 添加一个窗口到后台采集任务中
    func addSession(for source: WindowSource) {
        // 避免重复添加
        guard !activeSessions.contains(where: { $0.source.id == source.id }) else { return }
        
        let newSession = CaptureSession(source: source)
        activeSessions.append(newSession)
    }
    
    // 移除采集任务
    func removeSession(_ session: CaptureSession) {
        activeSessions.removeAll { $0.id == session.id }
    }
    
    // 核心功能：捕获单帧
    func captureFrame(for windowId: Int) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == CGWindowID(windowId) }) else { return nil }
            
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.showsCursor = true
            
            // 必须使用 MainActor 兼容的方式调用截图
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: config.width, height: config.height))
        } catch {
            logger.error("截图失败: \(error.localizedDescription)")
            return nil
        }
    }
}
