import Foundation

public enum SoundLibrary: String, CaseIterable, Sendable {
    case start1, start2, start3, start4
    case prestop
    case stop1, stop2, stop3, stop4
    case noresult1, noresult2, noresult3, noresult4
    case welcome
    case refine

    public var url: URL? {
        Bundle.module.url(forResource: rawValue, withExtension: "m4a")
    }
}
