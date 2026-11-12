import Foundation

/// How to turn one text into another by typing at the end: delete back to where they first
/// differ, then type the rest. TVs that type at the cursor (LG) apply edits this way.
public struct TextEdit: Equatable, Sendable {
    public let deleteCount: Int
    public let insert: String

    init(deleteCount: Int, insert: String) {
        self.deleteCount = deleteCount
        self.insert = insert
    }

    public init(from old: String, to new: String) {
        let shared = zip(old, new).prefix { $0 == $1 }.count
        deleteCount = old.count - shared
        insert = String(new.dropFirst(shared))
    }
}
