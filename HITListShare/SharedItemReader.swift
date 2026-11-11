import Foundation
import UniformTypeIdentifiers
import HITListCore

/// Reads what the host app handed the share sheet into one `SharedContent`: the first web address, the page's title
/// and the first text. Safari on iPhone and iPad hands the result of `ShareJavaScript.js` (address, title, selection);
/// other apps hand a URL, text, or both, with the page's title on the item. A file's address is never taken (the
/// activation rule offers HITList for addresses and text only).
enum SharedItemReader {
    static func read(_ items: [NSExtensionItem]) async -> SharedContent {
        var address: String?
        var pageTitle: String?
        var text: String?
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let page = await javaScriptResults(provider) {
                    address = address ?? nonBlank(page["URL"] as? String)
                    pageTitle = pageTitle ?? nonBlank(page["title"] as? String)
                    text = text ?? nonBlank(page["selection"] as? String)
                }
                if address == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(provider), !url.isFileURL {
                    address = url.absoluteString
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    text = nonBlank(await loadText(provider))
                }
            }
            let title = nonBlank(item.attributedTitle?.string)
            let content = nonBlank(item.attributedContentText?.string)
            // With an address, the item's words are the page's title (Safari on the Mac, many apps' links); without
            // one, they are the text being shared.
            if address != nil {
                pageTitle = pageTitle ?? title ?? content.flatMap(oneLine)
            } else {
                text = text ?? content
                pageTitle = pageTitle ?? title
            }
            if address != nil || text != nil { break }
        }
        return SharedContent(address: address, pageTitle: pageTitle, text: text).normalized
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// A title is one line; words over several lines are text, not a title.
    private static func oneLine(_ text: String) -> String? {
        text.contains(where: \.isNewline) ? nil : text
    }

    private static func javaScriptResults(_ provider: NSItemProvider) async -> [String: Any]? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) else { return nil }
        let dictionary = item as? NSDictionary
        #if os(iOS)
        return dictionary?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
        #else
        return dictionary?["NSExtensionJavaScriptPreprocessingResultsKey"] as? [String: Any]
        #endif
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) else { return nil }
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) else { return nil }
        if let string = item as? String { return string }
        if let attributed = item as? NSAttributedString { return attributed.string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        if let url = item as? URL, !url.isFileURL { return url.absoluteString }
        return nil
    }
}
