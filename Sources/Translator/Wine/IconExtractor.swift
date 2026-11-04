import AppKit
import Foundation

/// Pulls the embedded application icon out of a Windows .exe (PE file) so the library can show
/// the real icon instead of a generic document.
enum IconExtractor {
    private static let cache = NSCache<NSString, NSImage>()
    private static let missing = NSCache<NSString, NSNumber>()

    /// Returns a cached icon immediately when available.
    static func cachedIcon(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    /// Extracts (and caches) the icon. Safe to call from any thread.
    static func icon(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        if missing.object(forKey: key) != nil { return nil }
        guard url.pathExtension.lowercased() == "exe",
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let ico = icoData(fromPE: data),
              let image = NSImage(data: ico) else {
            missing.setObject(1, forKey: key)
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: - PE parsing

    private struct Section {
        let virtualAddress: Int
        let virtualSize: Int
        let rawPointer: Int
        let rawSize: Int
    }

    private struct ResourceEntry {
        let id: Int?            // nil for named entries
        let isDirectory: Bool
        let offset: Int         // relative to the resource section start
    }

    static func icoData(fromPE data: Data) -> Data? {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int? {
            guard o >= 0, o + 2 <= bytes.count else { return nil }
            return Int(bytes[o]) | Int(bytes[o + 1]) << 8
        }
        func u32(_ o: Int) -> Int? {
            guard o >= 0, o + 4 <= bytes.count else { return nil }
            return Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        }

        guard bytes.count > 64, bytes[0] == 0x4D, bytes[1] == 0x5A, // "MZ"
              let peOffset = u32(0x3C), u32(peOffset) == 0x0000_4550 else { return nil } // "PE\0\0"

        let coff = peOffset + 4
        guard let sectionCount = u16(coff + 2), let optionalSize = u16(coff + 16) else { return nil }
        let optional = coff + 20
        guard let magic = u16(optional) else { return nil }
        let dataDirectories = optional + (magic == 0x20B ? 112 : 96)
        guard let resourceRVA = u32(dataDirectories + 2 * 8), resourceRVA != 0 else { return nil }

        var sections: [Section] = []
        let sectionTable = optional + optionalSize
        for i in 0..<sectionCount {
            let s = sectionTable + i * 40
            guard let vSize = u32(s + 8), let vAddr = u32(s + 12),
                  let rSize = u32(s + 16), let rPtr = u32(s + 20) else { return nil }
            sections.append(Section(virtualAddress: vAddr, virtualSize: max(vSize, rSize), rawPointer: rPtr, rawSize: rSize))
        }
        func fileOffset(rva: Int) -> Int? {
            for s in sections where rva >= s.virtualAddress && rva < s.virtualAddress + s.virtualSize {
                return rva - s.virtualAddress + s.rawPointer
            }
            return nil
        }
        guard let resourceBase = fileOffset(rva: resourceRVA) else { return nil }

        func entries(at dirOffset: Int) -> [ResourceEntry] {
            let dir = resourceBase + dirOffset
            guard let named = u16(dir + 12), let ids = u16(dir + 14) else { return [] }
            let total = min(named + ids, 4096)
            var result: [ResourceEntry] = []
            for i in 0..<total {
                let e = dir + 16 + i * 8
                guard let name = u32(e), let target = u32(e + 4) else { break }
                let isNamed = name & 0x8000_0000 != 0
                result.append(ResourceEntry(
                    id: isNamed ? nil : name & 0xFFFF,
                    isDirectory: target & 0x8000_0000 != 0,
                    offset: target & 0x7FFF_FFFF
                ))
            }
            return result
        }

        /// Follows directory levels down to the first data entry and returns its bytes.
        func firstLeafData(_ entry: ResourceEntry, depth: Int = 0) -> Data? {
            guard depth < 4 else { return nil }
            if entry.isDirectory {
                for child in entries(at: entry.offset) {
                    if let found = firstLeafData(child, depth: depth + 1) { return found }
                }
                return nil
            }
            let leaf = resourceBase + entry.offset
            guard let rva = u32(leaf), let size = u32(leaf + 4),
                  let start = fileOffset(rva: rva), start + size <= bytes.count, size > 0 else { return nil }
            return Data(bytes[start..<(start + size)])
        }

        let types = entries(at: 0)
        guard let groupType = types.first(where: { $0.id == 14 && $0.isDirectory }),   // RT_GROUP_ICON
              let iconType = types.first(where: { $0.id == 3 && $0.isDirectory }) else { return nil } // RT_ICON

        let iconEntries = entries(at: iconType.offset)
        func iconImage(id: Int) -> Data? {
            guard let entry = iconEntries.first(where: { $0.id == id }) else { return nil }
            return firstLeafData(entry)
        }

        // The first icon group is the one Windows Explorer shows.
        for group in entries(at: groupType.offset) {
            guard let groupData = firstLeafData(group), groupData.count >= 6 else { continue }
            let g = [UInt8](groupData)
            let count = Int(g[4]) | Int(g[5]) << 8
            guard count > 0, groupData.count >= 6 + count * 14 else { continue }

            var images: [(header: [UInt8], data: Data)] = []
            for i in 0..<count {
                let e = 6 + i * 14
                let id = Int(g[e + 12]) | Int(g[e + 13]) << 8
                guard let image = iconImage(id: id) else { continue }
                images.append((header: Array(g[e..<(e + 12)]), data: image))
            }
            guard !images.isEmpty else { continue }

            // Rebuild a standalone .ico file: ICONDIR + ICONDIRENTRY[] + image data.
            var ico = Data([0, 0, 1, 0, UInt8(images.count & 0xFF), UInt8(images.count >> 8)])
            var offset = 6 + images.count * 16
            for image in images {
                var header = image.header
                // Bytes 8...11 hold the size; make sure it matches the data we actually have.
                let size = image.data.count
                header[8] = UInt8(size & 0xFF); header[9] = UInt8((size >> 8) & 0xFF)
                header[10] = UInt8((size >> 16) & 0xFF); header[11] = UInt8((size >> 24) & 0xFF)
                ico.append(contentsOf: header)
                ico.append(contentsOf: [UInt8(offset & 0xFF), UInt8((offset >> 8) & 0xFF),
                                        UInt8((offset >> 16) & 0xFF), UInt8((offset >> 24) & 0xFF)])
                offset += size
            }
            for image in images { ico.append(image.data) }
            return ico
        }
        return nil
    }
}
