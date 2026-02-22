import AppKit
import AVFoundation
import SwiftUI

/// An AppKit-backed video player that loops a bundled video with no controls.
public struct LoopingVideoPlayer: NSViewRepresentable {
    private let resourceName: String
    private let resourceExtension: String

    public init(_ resourceName: String, withExtension ext: String = "mp4") {
        self.resourceName = resourceName
        self.resourceExtension = ext
    }

    public func makeNSView(context: Context) -> _LoopingVideoNSView {
        let view = _LoopingVideoNSView()
        if let url = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension) {
            view.configure(with: url)
        }
        return view
    }

    public func updateNSView(_ nsView: _LoopingVideoNSView, context: Context) {}
}

public final class _LoopingVideoNSView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override public init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.allowsExternalPlayback = false

        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        self.layer?.addSublayer(layer)
        playerLayer = layer

        player.play()
    }

    override public func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}
