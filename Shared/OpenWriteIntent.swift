import AppIntents
import Foundation

/// Opens still. straight to a blank entry. Used by the Control Center control
/// (and so the Action Button / Lock Screen controls).
@available(iOS 18.0, *)
struct OpenWriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Write in still."
    static let description = IntentDescription("Open still. to a blank entry.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetShared.writeURL))
    }
}
