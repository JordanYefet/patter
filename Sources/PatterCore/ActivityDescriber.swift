import Foundation

/// Short, plain-language text about tool calls for the UI.
public enum ActivityDescriber {
    /// The detail to show under "Allow <tool>" when a permission is pending.
    public static func permissionDetail(tool: String, input: JSONObject?) -> String? {
        guard let input else { return nil }
        if let cmd = input.string("command") { return truncate(firstLine(cmd), 120) }
        if let path = input.string("file_path") { return path }
        if let url = input.string("url") { return url }
        if let pattern = input.string("pattern") { return pattern }
        return nil
    }

    static func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? s
    }

    public static func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
}
