/// Which column holds each component type: an open-addressing hash table from a type's identifier
/// to the position of its column.
///
/// Types are never removed, so the table needs no deletion. Keys hash by multiplying the
/// identifier's address by 2⁶⁴/φ and keeping the high bits (Fibonacci hashing), which spreads the
/// aligned addresses of type metadata evenly; lookup probes linearly from there.
///
/// - Complexity: Lookup is O(1) expected; insertion O(1) amortized. The table stays at most half
///   full.
@frozen
@usableFromInline
struct ColumnTable: Sendable {
    /// Each bucket's key, the address of a type's metadata, or 0 for an empty bucket.
    @usableFromInline var keys: [UInt] = []
    /// Each bucket's column position.
    @usableFromInline var positions: [Int] = []
    /// The number of keys, which is also the next column position.
    @usableFromInline var count = 0
    /// log2 of the bucket count.
    @usableFromInline var shift = 0
    #if DEBUG
    /// The keys a system with a declared access may look up while it runs, in debug builds; nil
    /// when any may be.
    @usableFromInline var permitted: Set<UInt>?
    #endif

    @inlinable
    init() {}

    @inlinable
    @inline(__always)
    func bucket(of key: UInt) -> Int {
        Int(truncatingIfNeeded: (key &* 0x9E37_79B9_7F4A_7C15) >> UInt(UInt.bitWidth - shift))
    }

    /// The column position of `type`, or nil if it has none.
    @inlinable
    @inline(__always)
    func position(of type: ObjectIdentifier) -> Int? {
        let key = UInt(bitPattern: type)
        #if DEBUG
        if let permitted, !permitted.contains(key) {
            undeclaredComponentAccess()
        }
        #endif
        guard count > 0 else { return nil }
        let mask = keys.count - 1
        var bucket = bucket(of: key)
        while true {
            let stored = keys[bucket]
            if stored == key { return positions[bucket] }
            if stored == 0 { return nil }
            bucket = (bucket + 1) & mask
        }
    }

    /// Records that `type`, which has no position yet, has `position`.
    @inlinable
    mutating func insert(_ type: ObjectIdentifier, at position: Int) {
        if (count + 1) * 2 > keys.count {
            grow()
        }
        place(UInt(bitPattern: type), position)
        count += 1
    }

    @inlinable
    mutating func place(_ key: UInt, _ position: Int) {
        let mask = keys.count - 1
        var bucket = bucket(of: key)
        while keys[bucket] != 0 {
            bucket = (bucket + 1) & mask
        }
        keys[bucket] = key
        positions[bucket] = position
    }

    @inline(never)
    @usableFromInline
    mutating func grow() {
        let oldKeys = keys
        let oldPositions = positions
        shift = max(shift + 1, 3)
        keys = Array(repeating: 0, count: 1 << shift)
        positions = Array(repeating: 0, count: 1 << shift)
        for (key, position) in zip(oldKeys, oldPositions) where key != 0 {
            place(key, position)
        }
    }
}

#if DEBUG
/// Traps for a system that reached a component type its access does not list.
@usableFromInline
@inline(never)
func undeclaredComponentAccess() -> Never {
    preconditionFailure("A system read or wrote a component type its access does not list")
}
#endif
