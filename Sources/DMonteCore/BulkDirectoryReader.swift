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

            let bufferEnd = buffer.advanced(by: bufferCapacity)
            var cursor = buffer
            for _ in 0..<count {
                let entryStart = cursor

                // The entry must at least contain its own length prefix.
                guard entryStart.advanced(by: MemoryLayout<UInt32>.size) <= bufferEnd else {
                    break
                }
                let entryLength = entryStart.loadUnaligned(as: UInt32.self)
                // A zero length never advances the cursor: bail to avoid an infinite loop.
                if entryLength == 0 {
                    break
                }
                // The claimed entry must lie entirely within the allocated buffer.
                guard entryStart.advanced(by: Int(entryLength)) <= bufferEnd else {
                    break
                }
                // All fixed-offset fields must stay within this entry's claimed extent.
                let entryEnd = entryStart.advanced(by: Int(entryLength))

                var fieldOffset = MemoryLayout<UInt32>.size

                // First attribute (we requested ATTR_CMN_RETURNED_ATTRS): the set of
                // attributes the kernel actually returned for this entry.
                let returnedOffset = fieldOffset
                guard entryStart.advanced(by: returnedOffset + MemoryLayout<attribute_set_t>.size) <= entryEnd else {
                    break
                }
                let returned = entryStart
                    .advanced(by: returnedOffset)
                    .loadUnaligned(as: attribute_set_t.self)
                fieldOffset += MemoryLayout<attribute_set_t>.size

                let nameMask = UInt32(truncatingIfNeeded: ATTR_CMN_NAME)
                let objTypeMask = UInt32(truncatingIfNeeded: ATTR_CMN_OBJTYPE)
                let allocMask = UInt32(truncatingIfNeeded: ATTR_FILE_ALLOCSIZE)
                let nameReturned = (returned.commonattr & nameMask) != 0
                let objTypeReturned = (returned.commonattr & objTypeMask) != 0
                let allocReturned = (returned.fileattr & allocMask) != 0

                let nameRefOffset = fieldOffset
                guard entryStart.advanced(by: nameRefOffset + MemoryLayout<attrreference_t>.size) <= entryEnd else {
                    break
                }
                let nameRef = entryStart
                    .advanced(by: nameRefOffset)
                    .loadUnaligned(as: attrreference_t.self)
                let namePtr = entryStart
                    .advanced(by: nameRefOffset + Int(nameRef.attr_dataoffset))
                fieldOffset += MemoryLayout<attrreference_t>.size

                let fsidOffset = fieldOffset
                guard entryStart.advanced(by: fsidOffset + MemoryLayout<fsid_t>.size) <= entryEnd else {
                    break
                }
                let entryFsid = entryStart
                    .advanced(by: fsidOffset)
                    .loadUnaligned(as: fsid_t.self)
                fieldOffset += MemoryLayout<fsid_t>.size

                let objTypeOffset = fieldOffset
                guard entryStart.advanced(by: objTypeOffset + MemoryLayout<UInt32>.size) <= entryEnd else {
                    break
                }
                let objType = entryStart
                    .advanced(by: objTypeOffset)
                    .loadUnaligned(as: UInt32.self)
                fieldOffset += MemoryLayout<UInt32>.size

                let allocOffset = fieldOffset
                guard entryStart.advanced(by: allocOffset + MemoryLayout<Int64>.size) <= entryEnd else {
                    break
                }
                let allocRaw = entryStart
                    .advanced(by: allocOffset)
                    .loadUnaligned(as: Int64.self)

                // Without a trustworthy name or object type we cannot classify the entry.
                guard nameReturned, objTypeReturned else {
                    cursor = entryEnd
                    continue
                }
                // The name buffer must lie within this entry's claimed extent.
                guard namePtr >= entryStart, namePtr < entryEnd else {
                    cursor = entryEnd
                    continue
                }
                let entryName = String(cString: namePtr.assumingMemoryBound(to: CChar.self))

                if entryName != "." && entryName != ".." {
                    let allocValid = allocReturned ? UInt64(max(0, allocRaw)) : 0
                    let size: UInt64 = (objType == vreg) ? allocValid : 0
                    entries.append(BulkEntry(
                        name: entryName,
                        isDirectory: objType == vdir,
                        isSymlink: objType == vlnk,
                        allocatedSize: size,
                        fsid: DiskFilesystemID(entryFsid)
                    ))
                }

                cursor = entryEnd
            }
        }

        return BulkDirectoryResult(fsid: dirFsid, entries: entries)
    }
}
