import Foundation

/// Moves a store file that exists but no longer decodes out of the way.
///
/// Every store in this package treats an undecodable file as an empty one, which is the right
/// thing to *show* — there is nothing usable in it and nothing the user could do at that moment.
/// The damage is what happens next: the store's first ordinary write lands on the same path and
/// overwrites the only copy of whatever was in there. Renaming it first costs nothing on the
/// healthy path (it never runs) and leaves the bytes on disk for a manual rescue.
///
/// `ScratchpadKit` deliberately does not use this: it salvages a damaged note in place and keeps
/// the file, which is a better answer where the payload is the user's own prose.
public enum CorruptStoreFile {
    /// Renames `url` to `<name>.corrupt`, or `<name>.corrupt-2`, `-3`… when earlier casualties are
    /// already sitting there. Returns where it went, or `nil` if there was nothing to move or the
    /// move failed — callers carry on either way, because failing to quarantine is not a reason to
    /// refuse to start.
    @discardableResult
    public static func quarantine(at url: URL) -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }

        guard let destination = availableDestination(for: url, manager: manager) else { return nil }
        guard (try? manager.moveItem(at: url, to: destination)) != nil else { return nil }
        return destination
    }

    /// The first free `.corrupt` name for `url`.
    ///
    /// Bounded rather than looping until it finds a gap: a directory that somehow already holds a
    /// hundred of these is a bug worth not compounding, and giving up here simply leaves the
    /// caller with today's behaviour.
    private static func availableDestination(for url: URL, manager: FileManager) -> URL? {
        let base = url.path + ".corrupt"
        if !manager.fileExists(atPath: base) { return URL(fileURLWithPath: base) }

        for suffix in 2...100 {
            let candidate = "\(base)-\(suffix)"
            if !manager.fileExists(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }
}
