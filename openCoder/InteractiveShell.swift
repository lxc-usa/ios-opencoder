import Foundation

/// 交互式 PTY shell 会话：打开后保持存活，可直接交互，支持 top/vi 等全屏程序。
///
/// 并发模型（Swift 6）：
/// - 本类是 `@MainActor`，只管 UI 状态（state/onData/pending）和输入事件的转发。
/// - 真正的 SSH 会话跑在 `SSHManager.runPTY`（SSHManager actor 隔离域）里；
///   `SSHClient` / `TTYOutput` / `TTYStdinWriter` 等非 Sendable 类型绝不跨 actor。
/// - 两域之间只传 Sendable 值：输入是 `AsyncStream<PTYInput>`，
///   输出是 `AsyncStream<[UInt8]>`，就绪信号是只捕获 Sendable continuation 的闭包。
/// - 实现：Citadel 的 `withPTY` 打开伪终端 + login shell；远端输出字节经输出流
///   交给 SwiftTerm 做 xterm 仿真；用户按键经输入流回写到 SSH 通道；视图尺寸变化
///   经输入流发 WindowChangeRequest 通知远端（top/vi 重排版靠它）。
@MainActor
final class InteractiveShell: ObservableObject {
    enum State {
        case connecting
        case connected
        case failed(String)
        case ended
    }

    @Published private(set) var state: State = .connecting

    /// 远端输出字节，主线程回调，由终端视图 feed 给仿真器。
    /// 视图尚未建好时的输出会暂存，设置回调后一次性补上，避免丢首屏提示符。
    var onData: (([UInt8]) -> Void)? {
        didSet {
            guard onData != nil else { return }
            let pending = pendingData
            pendingData.removeAll()
            for chunk in pending { onData?(chunk) }
        }
    }
    /// onData 设置前的暂存（上限约 256KB，防止无视图时无限堆积）。
    private var pendingData: [[UInt8]] = []
    private var pendingBytes = 0

    private var task: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?
    /// UI → 远端的输入流入口；nil 表示当前没有活跃会话。
    private var inputContinuation: AsyncStream<SSHManager.PTYInput>.Continuation?
    /// 视图先布局、会话未建好时暂存尺寸，start 时作为 PTY 初始尺寸。
    private var pendingResize: (cols: Int, rows: Int)?

    func start(server: ServerConfig) {
        guard task == nil else { return }
        // 上一会话残留的输入流（shell 自行退出的情况）：先结束，
        // 让旧的转发任务退出，避免写到已关闭的通道。
        inputContinuation?.finish()
        inputContinuation = nil
        pendingData.removeAll()
        pendingBytes = 0
        state = .connecting

        let (inputStream, inputCont) = AsyncStream<SSHManager.PTYInput>.makeStream()
        let (outputStream, outputCont) = AsyncStream<[UInt8]>.makeStream()
        let (readyStream, readyCont) = AsyncStream<Void>.makeStream()
        inputContinuation = inputCont

        let initialSize = pendingResize ?? (cols: 80, rows: 24)
        pendingResize = nil

        // 远端输出 → 终端仿真器（本任务继承 MainActor，直接调 didReceive）
        outputTask?.cancel()
        outputTask = Task { [weak self] in
            for await bytes in outputStream {
                self?.didReceive(bytes)
            }
        }
        // PTY 建好 → 切 connected（只取第一个信号）
        Task { [weak self] in
            for await _ in readyStream {
                self?.state = .connected
                break
            }
        }

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                server: server,
                cols: initialSize.cols, rows: initialSize.rows,
                input: inputStream,
                output: outputCont,
                onReady: {
                    readyCont.yield(())
                    readyCont.finish()
                }
            )
        }
    }

    /// 结束会话：先让远端 shell 自己退出（写 exit），再结束输入流、取消任务。
    /// 通道关闭后 runPTY 正常返回，会话干净结束。
    func stop() {
        if let cont = inputContinuation {
            inputContinuation = nil
            cont.yield(.bytes(Array("exit\n".utf8)))
            cont.finish()
        }
        task?.cancel()
        task = nil
        outputTask?.cancel()
        outputTask = nil
    }

    /// 用户按键 → 输入流 → SSH 通道（无活跃会话时直接丢弃）。
    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        inputContinuation?.yield(.bytes(bytes))
    }

    /// 终端视图尺寸变化 → 输入流 → 远端 WindowChangeRequest（top/vi 重排版靠它）。
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        if let cont = inputContinuation {
            cont.yield(.resize(cols: cols, rows: rows))
        } else {
            pendingResize = (cols, rows)
        }
    }

    // MARK: - 会话主循环（只经 Sendable 值与 SSHManager actor 打交道）

    private func run(
        server: ServerConfig,
        cols: Int, rows: Int,
        input: AsyncStream<SSHManager.PTYInput>,
        output: AsyncStream<[UInt8]>.Continuation,
        onReady: @Sendable @escaping () -> Void
    ) async {
        do {
            try await SSHManager.shared.runPTY(
                server: server, cols: cols, rows: rows,
                input: input, output: output, onReady: onReady
            )
            // runPTY 正常返回 = shell 已退出
            state = .ended
        } catch {
            // stop() 的取消不算失败
            state = Task.isCancelled ? .ended : .failed(describeSSHError(error))
        }
        inputContinuation?.finish()
        inputContinuation = nil
        task = nil
    }

    private func didReceive(_ bytes: [UInt8]) {
        if let onData {
            onData(bytes)
        } else if pendingBytes < 256 * 1024 {
            pendingData.append(bytes)
            pendingBytes += bytes.count
        }
    }
}
