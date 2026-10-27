import Foundation

/// Reads the repo root and current branch straight from `.git` — no `git`
/// process, so it is cheap enough to call on every Stop event.
public enum GitInfo {
    public struct Repo: Equatable, Sendable {
        public var root: String
        public var branch: String?
    }

    public static func repo(containing path: String, fileManager: FileManager = .default) -> Repo? {
        // Walk up with string paths: URL.deletingLastPathComponent() on "/" yields "/..".
        var current = (path as NSString).standardizingPath
        guard current.hasPrefix("/") else { return nil }
        for _ in 0..<64 {
            let dir = URL(fileURLWithPath: current, isDirectory: true)
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                let gitDir = isDir.boolValue ? dotGit : resolveGitFile(dotGit, base: dir)
                return Repo(root: current, branch: gitDir.flatMap { readBranch(gitDir: $0) })
            }
            if current == "/" { return nil }
            current = (current as NSString).deletingLastPathComponent
            if current.isEmpty { return nil }
        }
        return nil
    }

    /// Worktrees and submodules have a `.git` *file*: `gitdir: <path>`.
    static func resolveGitFile(_ file: URL, base: URL) -> URL? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let prefix = "gitdir:"
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let path = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path).standardizedFileURL
    }

    static func readBranch(gitDir: URL) -> String? {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = "ref: refs/heads/"
        if trimmed.hasPrefix(ref) { return String(trimmed.dropFirst(ref.count)) }
        // Detached HEAD: show the short sha.
        return trimmed.isEmpty ? nil : String(trimmed.prefix(7))
    }
}
