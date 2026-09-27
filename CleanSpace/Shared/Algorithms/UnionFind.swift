import Foundation

/// Disjoint-set with path compression and union by rank.
struct UnionFind {
    private var parent: [Int]
    private var rank: [UInt8]

    init(count: Int) {
        parent = Array(0..<max(count, 0))
        rank = Array(repeating: 0, count: max(count, 0))
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var current = x
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    @discardableResult
    mutating func union(_ a: Int, _ b: Int) -> Bool {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return false }
        if rank[ra] < rank[rb] {
            parent[ra] = rb
        } else if rank[ra] > rank[rb] {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] &+= 1
        }
        return true
    }
}
