import Foundation

/// Turns a tool call into a short, plain-language line for the UI.
///
///     Edit  {file_path: ".../apps/values.yaml"}  ->  "Editing values.yaml"
///     Bash  {command: "npm test -- --watch=false"} -> "Running npm test -- --watch=false"
public enum ActivityDescriber {
    public static func describe(tool: String, input: JSONObject?) -> String {
        let input = input ?? JSONObject([:])
        let file = input.string("file_path").map(fileName) ?? input.string("notebook_path").map(fileName)

        switch tool {
        case "Edit", "MultiEdit", "NotebookEdit":
            return "Editing \(file ?? "a file")"
        case "Write":
            return "Writing \(file ?? "a file")"
        case "Read":
            return "Reading \(file ?? "a file")"
        case "Bash", "PowerShell":
            if let cmd = input.string("command") { return "Running \(truncate(firstLine(cmd), 60))" }
            return "Running a command"
        case "Grep":
            if let p = input.string("pattern") { return "Searching for \u{201C}\(truncate(p, 40))\u{201D}" }
            return "Searching code"
        case "Glob":
            if let p = input.string("pattern") { return "Finding \(truncate(p, 40))" }
            return "Finding files"
        case "WebFetch":
            if let url = input.string("url"), let host = URL(string: url)?.host { return "Fetching \(host)" }
            return "Fetching a page"
        case "WebSearch":
            if let q = input.string("query") { return "Searching the web for \u{201C}\(truncate(q, 40))\u{201D}" }
            return "Searching the web"
        case "Task", "Agent":
            if let d = input.string("description") { return "Agent: \(truncate(d, 50))" }
            return "Running an agent"
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet":
            return "Updating the plan"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                // mcp__server__tool -> ["mcp", "server", "tool..."]
                if parts.count >= 3 {
                    let server = parts[1]
                    let name = parts[2...].joined(separator: "_")
                    return "Using \(server) · \(name)"
                }
            }
            return "Using \(tool)"
        }
    }

    /// The detail to show under "Allow <tool>" when a permission is pending.
    public static func permissionDetail(tool: String, input: JSONObject?) -> String? {
        guard let input else { return nil }
        if let cmd = input.string("command") { return truncate(firstLine(cmd), 120) }
        if let path = input.string("file_path") { return path }
        if let url = input.string("url") { return url }
        if let pattern = input.string("pattern") { return pattern }
        return nil
    }

    static func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    static func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? s
    }

    public static func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
}
