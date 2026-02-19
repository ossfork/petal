import Testing
@testable import MacXShared
@testable import MacXModels
@testable import MacXUI

@Test
func modulesCompile() {
    _ = MacXShared.self
    _ = MacXModels.self
    _ = MacXUI.self
    _ = MacXModelOption.defaultOption
    _ = MacXTranscriptionMode.verbatim
}
