import SwiftUI

public extension Image {
    static let appIcon = Image("appIcon", bundle: .module)
    static let accessibility = Image("accessibility", bundle: .module)
    static let microphone = Image("microphone", bundle: .module)
    static let qwen = Image("qwen", bundle: .module)
    static let mistral = Image("mistral", bundle: .module)
}

public enum AssetVideo {
    public static let waveVideo = "wave-video"
}
