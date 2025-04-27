const std = @import("std");
const tknz = @import("tokenize.zig");

pub const Nodekind = enum {
    kv,
    string,
    number,
    boolean,
    nil,
    object,
    array,
};

pub const Node = union(Nodekind) {
    kv: KV,
    string: String,
    number: Number,
    boolean: Boolean,
    nil: Nil,
    object: Children,
    array: Children,

    const KV = struct { lhs: *Node, rhs: *Node };
    const String = struct { v: []const u8 };
    const Number = struct { v: i8 };
    const Boolean = struct { v: bool };
    const Nil = struct {};
    const Children = struct { v: []*Node };

    /// Nodekindごとの初期化関数
    pub fn initKV(allocator: std.mem.Allocator, lhs: *Node, rhs: *Node) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .kv = KV{ .lhs = lhs, .rhs = rhs } };
        return node;
    }

    pub fn initString(allocator: std.mem.Allocator, v: []const u8) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .string = String{ .v = v } };
        return node;
    }

    pub fn initNumber(allocator: std.mem.Allocator, v: i8) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .number = Number{ .v = v } };
        return node;
    }

    pub fn initBoolean(allocator: std.mem.Allocator, v: bool) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .boolean = Boolean{ .v = v } };
        return node;
    }

    pub fn initNil(allocator: std.mem.Allocator) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .nil = Nil{} };
        return node;
    }

    pub fn initObject(allocator: std.mem.Allocator, children: []*Node) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .object = Children{ .v = children } };
        return node;
    }

    pub fn initArray(allocator: std.mem.Allocator, children: []*Node) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{ .array = Children{ .v = children } };
        return node;
    }
};

pub const ParseError = error{
    UnexpectedToken,
    OutOfMemory,
};

var attending: ?*tknz.token = undefined;

fn current() ?*tknz.token {
    return attending.?.next;
}

fn advance() void {
    if (attending != null) {
        const next = attending.?.next;
        attending = next;
    }
}

fn consume(kind: tknz.tokenkind) ?*tknz.token {
    if (current() != null and current().?.kind == kind) {
        const v = current();
        advance();
        return v;
    }
    return null;
}

fn expect(kind: tknz.tokenkind) ParseError!*tknz.token {
    const v = consume(kind);
    if (v != null) {
        return v.?;
    }
    return ParseError.UnexpectedToken;
}

fn key(allocator: std.mem.Allocator) ParseError!*Node {
    const str = expect(tknz.tokenkind.string) catch return ParseError.UnexpectedToken;
    return Node.initString(allocator, str.raw) catch return ParseError.OutOfMemory;
}

fn value(allocator: std.mem.Allocator) ParseError!*Node {
    var v: ?*tknz.token = null;
    v = consume(tknz.tokenkind.string);
    if (v != null) {
        return Node.initString(allocator, v.?.raw) catch return ParseError.OutOfMemory;
    }

    return ParseError.UnexpectedToken;
}

fn kv(allocator: std.mem.Allocator) ParseError!*Node {
    const k = key(allocator) catch return ParseError.UnexpectedToken;
    _ = expect(tknz.tokenkind.colon) catch return ParseError.UnexpectedToken;
    const v = value(allocator) catch return ParseError.UnexpectedToken;
    return Node.initKV(allocator, k, v) catch return ParseError.OutOfMemory;
}

fn object(allocator: std.mem.Allocator) ParseError!*Node {
    var children = std.ArrayList(*Node).init(allocator);
    while (true) {
        // }を見つけたら抜ける
        if (consume(tknz.tokenkind.rcb) != null) {
            break;
        }
        const pair = kv(allocator) catch return ParseError.UnexpectedToken;
        try children.append(pair);
    }
    return Node.initObject(allocator, try children.toOwnedSlice()) catch return ParseError.OutOfMemory;
}

fn array(allocator: std.mem.Allocator) ParseError!*Node {
    _ = allocator;
    return ParseError.UnexpectedToken;
}

pub fn parse(allocator: std.mem.Allocator, user_input: *tknz.token) ParseError!*Node {
    const head = tknz.token.initIllegal(allocator) catch unreachable;
    head.next = user_input;
    attending = head;

    if (consume(tknz.tokenkind.lcb) != null) {
        return object(allocator);
    }
    // TODO : [
    return ParseError.UnexpectedToken;
}

fn nodesEqual(a: *Node, b: *Node) bool {
    // 異なるタグなら不一致
    if (@intFromEnum(a.*) != @intFromEnum(b.*)) return false;

    switch (a.*) {
        .kv => |kvA| switch (b.*) {
            .kv => |kvB| return nodesEqual(kvA.lhs, kvB.lhs) and nodesEqual(kvA.rhs, kvB.rhs),
            else => return false,
        },
        .string => |strA| switch (b.*) {
            .string => |strB| return std.mem.eql(u8, strA.v, strB.v),
            else => return false,
        },
        .number => |numA| switch (b.*) {
            .number => |numB| return numA.v == numB.v,
            else => return false,
        },
        .boolean => |boolA| switch (b.*) {
            .boolean => |boolB| return boolA.v == boolB.v,
            else => return false,
        },
        .nil =>
        // nil 同士なら OK
        return true,
        .object => |objA| switch (b.*) {
            .object => |objB| {
                if (objA.v.len != objB.v.len) return false;
                for (objA.v, 0..) |childA, i| {
                    if (!nodesEqual(childA, objB.v[i])) return false;
                }
                return true;
            },
            else => return false,
        },
        .array => |arrA| switch (b.*) {
            .array => |arrB| {
                if (arrA.v.len != arrB.v.len) return false;
                for (arrA.v, 0..) |childA, i| {
                    if (!nodesEqual(childA, arrB.v[i])) return false;
                }
                return true;
            },
            else => return false,
        },
    }
}

test "parse" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // unexpected error
    var tokens = tknz.tokenize(arena.allocator(), "") catch unreachable;
    try std.testing.expectEqual(ParseError.UnexpectedToken, parse(arena.allocator(), tokens));

    // empty obj
    var want = Node.initObject(arena.allocator(), &.{}) catch unreachable;
    tokens = tknz.tokenize(arena.allocator(), "{}") catch unreachable;
    var got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));

    // string-kv
    const w_key = Node.initString(arena.allocator(), "key") catch unreachable;
    const w_val = Node.initString(arena.allocator(), "value") catch unreachable;
    const w_kv = Node.initKV(arena.allocator(), w_key, w_val) catch unreachable;
    want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv})) catch unreachable;
    tokens = tknz.tokenize(arena.allocator(), "{\"key\":\"value\"}") catch unreachable;
    got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}
