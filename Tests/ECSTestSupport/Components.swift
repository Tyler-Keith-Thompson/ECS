// Component and resource types shared by the test targets. Data only.

import WorldModule

public struct Position: Component, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Velocity: Component, Hashable {
    public var dx: Double
    public var dy: Double
    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
}

public struct Health: Component, Hashable {
    public var current: Int
    public init(_ current: Int) { self.current = current }
}

public struct Name: Component, Hashable {
    public var text: String
    public init(_ text: String) { self.text = text }
}

/// A marker: no stored properties.
public struct Frozen: Component, Hashable {
    public init() {}
}

/// Three interchangeable integer components for randomized tests.
public struct First: Component, Hashable {
    public var value: Int
    public init(_ value: Int) { self.value = value }
}

public struct Second: Component, Hashable {
    public var value: Int
    public init(_ value: Int) { self.value = value }
}

public struct Third: Component, Hashable {
    public var value: Int
    public init(_ value: Int) { self.value = value }
}

public struct Clock: Resource, Hashable {
    public var ticks: Int
    public init(ticks: Int) { self.ticks = ticks }
}

public struct Gravity: Resource, Hashable {
    public var acceleration: Double
    public init(acceleration: Double) { self.acceleration = acceleration }
}
