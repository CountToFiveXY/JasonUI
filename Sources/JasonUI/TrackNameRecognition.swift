import Foundation

/// Reassembles wrapped captions only when the complete name exists in the catalogue.
enum TrackNameRecognition {
    static func names(from input: [RecognizedLine], catalogue: [MapTrackSummary]) -> [String] {
        let lines = input.filter { !key($0.text).isEmpty }
        let trackKeys = Set(catalogue.flatMap { [key($0.id), key($0.name), key($0.chineseName ?? "")] }.filter { !$0.isEmpty })
        let mapKeys = Set(catalogue.flatMap { [key($0.mapName), key($0.mapChineseName ?? "")] }.filter { !$0.isEmpty })
        var prefixes = Set<String>()
        for name in trackKeys {
            var prefix = ""
            for character in name {
                prefix.append(character)
                prefixes.insert(prefix)
            }
        }
        var consumed = Set<Int>()
        var entries: [(name: String, rect: CGRect?)] = []
        for start in lines.indices where !consumed.contains(start) {
            var best: [Int] = []
            func extend(_ path: [Int], _ name: String) {
                guard prefixes.contains(name) else { return }
                if trackKeys.contains(name), path.count > best.count { best = path }
                let last = path.last!
                for next in lines.indices where !consumed.contains(next) && !path.contains(next) {
                    let adjacent: Bool
                    if let upper = lines[last].bounds?.rect, let lower = lines[next].bounds?.rect {
                        let overlap = min(upper.maxX, lower.maxX) - max(upper.minX, lower.minX)
                        let gap = lower.minY - upper.maxY
                        adjacent = upper.width > 0 && lower.width > 0 && upper.height > 0 && lower.height > 0
                            && lower.minY > upper.minY + min(upper.height, lower.height) * 0.5
                            && gap >= -min(upper.height, lower.height) * 0.25
                            && gap <= max(upper.height, lower.height) * 1.5
                            && overlap >= min(upper.width, lower.width) * 0.5
                            && abs(upper.midX - lower.midX) <= max(upper.width, lower.width) * 0.5
                    } else {
                        // Compatibility with older backends that return only text.
                        adjacent = next == last + 1
                    }
                    if adjacent { extend(path + [next], name + key(lines[next].text)) }
                }
            }
            extend([start], key(lines[start].text))
            if best.isEmpty {
                if !mapKeys.contains(key(lines[start].text)) {
                    entries.append((lines[start].text, lines[start].bounds?.rect))
                }
                continue
            }
            consumed.formUnion(best)
            let rectangles = best.compactMap { lines[$0].bounds?.rect }
            let rect = rectangles.count == best.count
                ? rectangles.dropFirst().reduce(rectangles[0]) { $0.union($1) } : nil
            entries.append((best.map { lines[$0].text }.joined(separator: " "), rect))
        }

        // Captions at different heights still belong to the same horizontal strip.
        // Group by vertical overlap, then restore left-to-right card order.
        guard entries.allSatisfy({ $0.rect != nil }) else { return entries.map(\.name) }
        var rows: [(top: CGFloat, bottom: CGFloat, items: [(name: String, rect: CGRect?)])] = []
        for entry in entries.sorted(by: { $0.rect!.minY < $1.rect!.minY }) {
            let rect = entry.rect!
            if let row = rows.firstIndex(where: { rect.minY < $0.bottom && rect.maxY > $0.top }) {
                rows[row].top = max(rows[row].top, rect.minY)
                rows[row].bottom = min(rows[row].bottom, rect.maxY)
                rows[row].items.append(entry)
            } else {
                rows.append((rect.minY, rect.maxY, [entry]))
            }
        }
        return rows.sorted { $0.top < $1.top }.flatMap { row in
            row.items.sorted { $0.rect!.minX < $1.rect!.minX }.map(\.name)
        }
    }

    private static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
