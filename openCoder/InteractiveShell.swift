import Foundation
import Citadel
import NIOSSH
import NIO

/// 交互式 PTY shell 会话：打开后保持存活，可直接交互，支持 top/vi 等全屏程序。
///
/// 实现：Citadel 的 `withPTY` 打开伪终端 + login shell；远端输出字节经 `onData`
/// 交给 SwiftTerm 做 xterm 仿真；用户按键经 `send` 回写到 SSH 通道；视图尺寸变化
/// 经 `resize` 发 WindowChangeRequest 通知远端（top/vi 重排版靠它）。
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
    private var writer: TTYStdinWriter?
    /// 视图先布局、SSH 后连上时，暂存尺寸等连上后补发。
    private var pendingResize: (cols: Int, rows: Int)?

    func start(server: ServerConfig) {
        guard task == nil else { return }
        writer = nil
        pendingData.removeAll()
        pendingBytes = 0
        state = .connecting
        task = Task { [weak self] in
            await self?.run(server: server)
        }
    }

    /// 结束会话：让远端 shell 自己退出，通道随之关闭，会话干净结束。
    func stop() {
        if let writer {
            self.writer = nil
            Task { try? await writer.write(ByteBuffer(string: "exit\n")) }
        }
        task?.cancel()
        task = nil
    }

    /// 用户按键 → SSH 通道。
    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, let writer else { return }
        var buffer = ByteBuffer()
        buffer.writeBytes(bytes)
        Task { try? await writer.write(buffer) }
    }

    /// 终端视图尺寸变化 → 通知远端 PTY。
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        guard let writer else {
            pendingResize = (cols, rows)
            return
        }
        Task {
            try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }

    // MARK: - 会话主循环

    private func run(server: ServerConfig) async {
        do {
            let client = try await SSHManager.shared.client(for: server)
            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: 80,
                terminalRowHeight: 24,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:])
            )
            try await client.withPTY(request) { inbound, outbound in
                await self.didConnect(outbound)
                do {
                    for try await output in inbound {
                        let bytes: [UInt8]
                        switch output {
                        case .stdout(let buffer), .stderr(let buffer):
                            bytes = Array(buffer.readableBytesView)
                        }
                        if !bytes.isEmpty {
                            await self.didReceive(bytes)
                        }
                    }
                } catch {
                    // 通道关闭或出错：perform 返回后 withPTY 会关闭通道
                }
                await self.didDisconnect()
            }
            // withPTY 正常返回 = perform 走完 = shell 已退出
            ended()
        } catch {
            state = .failed(describeSSHError(error))
        }
        task = nil
    }

    private func didConnect(_ writer: TTYStdinWriter) {
        self.writer = writer
        state = .connected
        if let pending = pendingResize {
            pendingResize = nil
            resize(cols: pending.cols, rows: pending.rows)
        }
    }

    private func didReceive(_ bytes: [UInt8]) {
        if let onData {
            onData(bytes)
        } else if pendingBytes < 256 * 1024 {
            pendingData.append(bytes)
            pendingBytes += bytes.count
        }
    }

    private func didDisconnect() {
        writer = nil
    }

    private func ended() {
        // stop() 触发的退出不算异常：task 已被置 nil
        state = .ended
    }
}
