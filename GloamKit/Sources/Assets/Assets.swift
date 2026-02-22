import SwiftUI

public extension Image {
    static let appIcon = Image("appIcon", bundle: .module)
    static let accessibility = Image("accessibility", bundle: .module)
    static let microphone = Image("microphone", bundle: .module)
}

public enum AssetVideo {
    public static let waveVideo = "wave-video"
}
