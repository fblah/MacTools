import Darwin
import Foundation

public struct DiskFilesystemID: Equatable, Hashable, Sendable {
    let raw: UInt64

    init(_ id: fsid_t) {
        let lo = UInt64(UInt32(bitPattern: id.val.0))
        let hi = UInt64(UInt32(bitPattern: id.val.1))
        raw = (hi << 32) | lo
    }
}

struct BulkEntry: Sendable {
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let allocatedSize: UInt64
    let fsid: DiskFilesystemID
}

struct BulkDirectoryResult: Sendable {
    let fsid: DiskFilesystemID
    let entries: [BulkEntry]
}

enum BulkDirectoryReader {
    private static let bufferCapacity = 64 * 1024
    private static let vreg: UInt32 = 1
    private static let vdir: UInt32 = 2
    private static let vlnk: UInt32 = 5

    static func read(at path: String) -> BulkDirectoryResult? {
        let fd = path.withCString { open($0, O_RDONLY | O_DIRECTORY, 0) }
        guard fd >= 0 else {
            return nil
        }
        defer { Darwin.close(fd) }

        var fsStat = statfs()
        guard fstatfs(fd, &fsStat) == 0 else {
            return nil
        }
        let dirFsid = DiskFilesystemID(fsStat.f_fsid)

        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = UInt32(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS)
            | UInt32(truncatingIfNeeded: ATTR_CMN_NAME)
            | UInt32(truncatingIfNeeded: ATTR_CMN_FSID)
            | UInt32(truncatingIfNeeded: ATTR_CMN_OBJTYPE)
        attrList.fileattr = UInt32(truncatingIfNeeded: ATTR_FILE_ALLOCSIZE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferCapacity, alignment: 16)
        defer { buffer.deallocate() }

        let options = UInt64(FSOPT_NOFOLLOW) | UInt64(FSOPT_PACK_INVAL_ATTRS)
        var entries: [BulkEntry] = []

        while true {
            let count = getattrlistbulk(fd, &attrList, buffer, bufferCapacity, options)
            if count <= 0 {
                break
            }

            var cursor = buffer
            for _ in 0..<count {
                let entryStart = cursor
                let entryLength = entryStart.loadUnaligned(as: UInt32.self)
                var fieldOffset = MemoryLayout<UInt32>.size

                fieldOffset += MemoryLayout<attribute_set_t>.size

                let nameRefOffset = fieldOffset
                let nameRef = entryStart
                    .advanced(by: nameRefOffset)
                    .loadUnaligned(as: attrreference_t.self)
                let namePtr = entryStart
                    .advanced(by: nameRefOffset + Int(nameRef.attr_dataoffset))
                let entryName = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
                fieldOffset += MemoryLayout<attrreference_t>.size

                let entryFsid = entryStart
                    .advanced(by: fieldOffset)
                    .loadUnaligned(as: fsid_t.self)
                fieldOffset += MemoryLayout<fsid_t>.size

                let objType = entryStart
                    .advanced(by: fieldOffset)
                    .loadUnaligned(as: UInt32.self)
                fieldOffset += MemoryLayout<UInt32>.size

                let allocRaw = entryStart
                    .advanced(by: fieldOffset)
                    .loadUnaligned(as: Int64.self)

                if entryName != "." && entryName != ".." {
                    let size: UInt64 = (objType == vreg) ? UInt64(max(0, allocRaw)) : 0
                    entries.append(BulkEntry(
                        name: entryName,
                        isDirectory: objType == vdir,
                        isSymlink: objType == vlnk,
                        allocatedSize: size,
                        fsid: DiskFilesystemID(entryFsid)
                    ))
                }

                cursor = entryStart.advanced(by: Int(entryLength))
            }
        }

        return BulkDirectoryResult(fsid: dirFsid, entries: entries)
    }
}
