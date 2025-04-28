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
    const Number = struct { v: []const u8 };
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

    pub fn initNumber(allocator: std.mem.Allocator, v: []const u8) !*Node {
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
    // string
    v = consume(tknz.tokenkind.string);
    if (v != null) {
        return Node.initString(allocator, v.?.raw) catch return ParseError.OutOfMemory;
    }
    // number
    v = consume(tknz.tokenkind.number);
    if (v != null) {
        return Node.initNumber(allocator, v.?.raw) catch return ParseError.OutOfMemory;
    }
    // boolean true
    v = consume(tknz.tokenkind.true);
    if (v != null) {
        return Node.initBoolean(allocator, true) catch return ParseError.OutOfMemory;
    }
    // boolean false
    v = consume(tknz.tokenkind.false);
    if (v != null) {
        return Node.initBoolean(allocator, false) catch return ParseError.OutOfMemory;
    }
    // null
    v = consume(tknz.tokenkind.nil);
    if (v != null) {
        return Node.initNil(allocator) catch return ParseError.OutOfMemory;
    }
    // object
    v = consume(tknz.tokenkind.lcb);
    if (v != null) {
        return object(allocator);
    }
    // array
    v = consume(tknz.tokenkind.lsb);
    if (v != null) {
        return array(allocator);
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
        // ,が見つからなければ
        if (consume(tknz.tokenkind.comma) == null) {
            // }があるはず
            _ = try expect(tknz.tokenkind.rcb);
            break;
        }
        // ,}はダメ
        if (consume(tknz.tokenkind.rcb) != null) {
            return ParseError.UnexpectedToken;
        }
    }
    return Node.initObject(allocator, try children.toOwnedSlice()) catch return ParseError.OutOfMemory;
}

fn array(allocator: std.mem.Allocator) ParseError!*Node {
    var children = std.ArrayList(*Node).init(allocator);
    while (consume(tknz.tokenkind.eof) == null) { // !is_eof
        // ]を見つけたら抜ける
        if (consume(tknz.tokenkind.rsb) != null) {
            break;
        }
        const child = value(allocator) catch return ParseError.UnexpectedToken;
        try children.append(child);
        // ,が見つからなければ
        if (consume(tknz.tokenkind.comma) == null) {
            // ]があるはず
            _ = try expect(tknz.tokenkind.rsb);
            break;
        }
        // ,]はダメ
        if (consume(tknz.tokenkind.rsb) != null) {
            return ParseError.UnexpectedToken;
        }
    }
    return Node.initArray(allocator, try children.toOwnedSlice()) catch return ParseError.OutOfMemory;
}

pub fn parse(allocator: std.mem.Allocator, user_input: *tknz.token) ParseError!*Node {
    const head = tknz.token.initIllegal(allocator) catch unreachable;
    head.next = user_input;
    attending = head;

    if (consume(tknz.tokenkind.lcb) != null) {
        return object(allocator);
    }
    if (consume(tknz.tokenkind.lsb) != null) {
        return array(allocator);
    }
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
            .number => |numB| return std.mem.eql(u8, numA.v, numB.v),
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

test "unexpect error" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // unexpected error
    const tokens = tknz.tokenize(arena.allocator(), "", true) catch unreachable;
    try std.testing.expectEqual(ParseError.UnexpectedToken, parse(arena.allocator(), tokens));
}

test "empty object" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const want = Node.initObject(arena.allocator(), &.{}) catch unreachable;
    const tokens = tknz.tokenize(arena.allocator(), "{}", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "string-kv" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const w_key = Node.initString(arena.allocator(), "key") catch unreachable;
    const w_val = Node.initString(arena.allocator(), "value") catch unreachable;
    const w_kv = Node.initKV(arena.allocator(), w_key, w_val) catch unreachable;
    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv})) catch unreachable;
    const tokens = tknz.tokenize(arena.allocator(), "{\"key\":\"value\"}", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "string-array" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const w_a = Node.initString(arena.allocator(), "a") catch unreachable;
    const w_b = Node.initString(arena.allocator(), "b") catch unreachable;
    const w_c = Node.initString(arena.allocator(), "c") catch unreachable;
    const want = Node.initArray(arena.allocator(), @constCast(&[_]*Node{ w_a, w_b, w_c })) catch unreachable;
    const tokens = tknz.tokenize(arena.allocator(), "[\"a\", \"b\", \"c\"]", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "object in object" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // { "john": { "type": "human" } }
    // { "type": "human" }
    const w_k_type = Node.initString(arena.allocator(), "type") catch unreachable;
    const w_v_human = Node.initString(arena.allocator(), "human") catch unreachable;
    const w_kv_human = Node.initKV(arena.allocator(), w_k_type, w_v_human) catch unreachable;
    const w_obj_child = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv_human})) catch unreachable;
    // { "john": ... }
    const w_k_john = Node.initString(arena.allocator(), "john") catch unreachable;
    const w_kv_john = Node.initKV(arena.allocator(), w_k_john, w_obj_child) catch unreachable;
    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv_john})) catch unreachable;
    const tokens = tknz.tokenize(arena.allocator(), "{ \"john\": { \"type\": \"human\" } }", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "object with array" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // { "children": [ "john", "tom", "candy" ] }
    // [ "john", "tom", "candy" ]
    const w_john = Node.initString(arena.allocator(), "john") catch unreachable;
    const w_tom = Node.initString(arena.allocator(), "tom") catch unreachable;
    const w_candy = Node.initString(arena.allocator(), "candy") catch unreachable;
    const w_children_array = Node.initArray(arena.allocator(), @constCast(&[_]*Node{ w_john, w_tom, w_candy })) catch unreachable;
    // { "children": ... }
    const w_k_children = Node.initString(arena.allocator(), "children") catch unreachable;
    const w_kv_children = Node.initKV(arena.allocator(), w_k_children, w_children_array) catch unreachable;
    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv_children})) catch unreachable;
    const tokens = tknz.tokenize(arena.allocator(), "{ \"children\": [ \"john\", \"tom\", \"candy\" ] }", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "multiple kv pairs" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // { "key1": "value1", "key2": "value2" }
    // "key1": "value1"
    const w_key1 = Node.initString(arena.allocator(), "key1") catch unreachable;
    const w_val1 = Node.initString(arena.allocator(), "value1") catch unreachable;
    const w_kv1 = Node.initKV(arena.allocator(), w_key1, w_val1) catch unreachable;
    // "key2": "value2"
    const w_key2 = Node.initString(arena.allocator(), "key2") catch unreachable;
    const w_val2 = Node.initString(arena.allocator(), "value2") catch unreachable;
    const w_kv2 = Node.initKV(arena.allocator(), w_key2, w_val2) catch unreachable;
    // { ..., ... }
    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ w_kv1, w_kv2 })) catch unreachable;
    const tokens = tknz.tokenize(arena.allocator(), "{ \"key1\": \"value1\", \"key2\": \"value2\" }", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "object with array of objects" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // { "children": [ {"name":"john", "sex": "male"}, {"name": "tom", "sex": "male"}, {"name": "candy", "sex": "female"} ] }
    // john
    const w_john_name_key = Node.initString(arena.allocator(), "name") catch unreachable;
    const w_john_name_val = Node.initString(arena.allocator(), "john") catch unreachable;
    const w_john_name_kv = Node.initKV(arena.allocator(), w_john_name_key, w_john_name_val) catch unreachable;
    const w_john_sex_key = Node.initString(arena.allocator(), "sex") catch unreachable;
    const w_john_sex_val = Node.initString(arena.allocator(), "male") catch unreachable;
    const w_john_sex_kv = Node.initKV(arena.allocator(), w_john_sex_key, w_john_sex_val) catch unreachable;
    const w_john_obj = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ w_john_name_kv, w_john_sex_kv })) catch unreachable;

    // tom
    const w_tom_name_key = Node.initString(arena.allocator(), "name") catch unreachable;
    const w_tom_name_val = Node.initString(arena.allocator(), "tom") catch unreachable;
    const w_tom_name_kv = Node.initKV(arena.allocator(), w_tom_name_key, w_tom_name_val) catch unreachable;
    const w_tom_sex_key = Node.initString(arena.allocator(), "sex") catch unreachable;
    const w_tom_sex_val = Node.initString(arena.allocator(), "male") catch unreachable;
    const w_tom_sex_kv = Node.initKV(arena.allocator(), w_tom_sex_key, w_tom_sex_val) catch unreachable;
    const w_tom_obj = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ w_tom_name_kv, w_tom_sex_kv })) catch unreachable;

    // candy
    const w_candy_name_key = Node.initString(arena.allocator(), "name") catch unreachable;
    const w_candy_name_val = Node.initString(arena.allocator(), "candy") catch unreachable;
    const w_candy_name_kv = Node.initKV(arena.allocator(), w_candy_name_key, w_candy_name_val) catch unreachable;
    const w_candy_sex_key = Node.initString(arena.allocator(), "sex") catch unreachable;
    const w_candy_sex_val = Node.initString(arena.allocator(), "female") catch unreachable;
    const w_candy_sex_kv = Node.initKV(arena.allocator(), w_candy_sex_key, w_candy_sex_val) catch unreachable;
    const w_candy_obj = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ w_candy_name_kv, w_candy_sex_kv })) catch unreachable;

    // object array
    const w_children_array = Node.initArray(arena.allocator(), @constCast(&[_]*Node{ w_john_obj, w_tom_obj, w_candy_obj })) catch unreachable;

    // children
    const w_k_children = Node.initString(arena.allocator(), "children") catch unreachable;
    const w_kv_children = Node.initKV(arena.allocator(), w_k_children, w_children_array) catch unreachable;

    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv_children})) catch unreachable;

    const tokens = tknz.tokenize(arena.allocator(), "{ \"children\": [ {\"name\":\"john\", \"sex\": \"male\"}, {\"name\": \"tom\", \"sex\": \"male\"}, {\"name\": \"candy\", \"sex\": \"female\"} ] }", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;

    // 9. 比較
    try std.testing.expect(nodesEqual(want, got));
}

test "number" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // 整数値のテスト
    const w_int_key = Node.initString(arena.allocator(), "integer") catch unreachable;
    const w_int_val = Node.initNumber(arena.allocator(), "42") catch unreachable;
    const w_int_kv = Node.initKV(arena.allocator(), w_int_key, w_int_val) catch unreachable;

    // 浮動小数点数のテスト
    const w_float_key = Node.initString(arena.allocator(), "float") catch unreachable;
    const w_float_val = Node.initNumber(arena.allocator(), "3.14") catch unreachable;
    const w_float_kv = Node.initKV(arena.allocator(), w_float_key, w_float_val) catch unreachable;

    // 負の数のテスト
    const w_neg_key = Node.initString(arena.allocator(), "negative") catch unreachable;
    const w_neg_val = Node.initNumber(arena.allocator(), "-10") catch unreachable;
    const w_neg_kv = Node.initKV(arena.allocator(), w_neg_key, w_neg_val) catch unreachable;

    // オブジェクトの作成
    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ w_int_kv, w_float_kv, w_neg_kv })) catch unreachable;

    // JSONのパース
    const json_str =
        \\{
        \\  "integer": 42,
        \\  "float": 3.14,
        \\  "negative": -10
        \\}
    ;
    const tokens = tknz.tokenize(arena.allocator(), json_str, true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;

    // 結果の検証
    try std.testing.expect(nodesEqual(want, got));
}

test "bool" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // true のテスト
    const w_key_true = Node.initString(arena.allocator(), "flag") catch unreachable;
    const w_val_true = Node.initBoolean(arena.allocator(), true) catch unreachable;
    const w_kv_true = Node.initKV(arena.allocator(), w_key_true, w_val_true) catch unreachable;
    const want_true = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv_true})) catch unreachable;
    const tokens_true = tknz.tokenize(arena.allocator(), "{\"flag\":true}", true) catch unreachable;
    const got_true = parse(arena.allocator(), tokens_true) catch unreachable;
    try std.testing.expect(nodesEqual(want_true, got_true));

    // false のテスト
    const w_key_false = Node.initString(arena.allocator(), "flag") catch unreachable;
    const w_val_false = Node.initBoolean(arena.allocator(), false) catch unreachable;
    const w_kv_false = Node.initKV(arena.allocator(), w_key_false, w_val_false) catch unreachable;
    const want_false = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv_false})) catch unreachable;
    const tokens_false = tknz.tokenize(arena.allocator(), "{\"flag\":false}", true) catch unreachable;
    const got_false = parse(arena.allocator(), tokens_false) catch unreachable;
    try std.testing.expect(nodesEqual(want_false, got_false));
}

test "null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const w_key = Node.initString(arena.allocator(), "nothing") catch unreachable;
    const w_val = Node.initNil(arena.allocator()) catch unreachable;
    const w_kv = Node.initKV(arena.allocator(), w_key, w_val) catch unreachable;
    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{w_kv})) catch unreachable;

    const tokens = tknz.tokenize(arena.allocator(), "{\"nothing\":null}", true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;
    try std.testing.expect(nodesEqual(want, got));
}

test "large complex api response" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const json_str =
        \\{
        \\  "stats": {
        \\    "total_count": 100,
        \\    "next_page": null,
        \\    "errors": []
        \\  },
        \\  "users": [
        \\    {
        \\      "id": 1,
        \\      "name": "Alice",
        \\      "active": true,
        \\      "roles": ["admin", "editor"],
        \\      "metadata": {
        \\        "last_login": "2025-04-28T12:34:56Z",
        \\        "preferences": ["email", "sms"]
        \\      }
        \\    },
        \\    {
        \\      "id": 2,
        \\      "name": "Bob",
        \\      "active": false,
        \\      "roles": ["viewer"],
        \\      "metadata": {
        \\        "last_login": "2025-04-27T08:15:00Z",
        \\        "preferences": ["push"]
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const tokens = tknz.tokenize(arena.allocator(), json_str, true) catch unreachable;
    const got = parse(arena.allocator(), tokens) catch unreachable;

    // --- build expected Node tree ---
    // stats
    const k_total = Node.initString(arena.allocator(), "total_count") catch unreachable;
    const v_total = Node.initNumber(arena.allocator(), "100") catch unreachable;
    const kv_total = Node.initKV(arena.allocator(), k_total, v_total) catch unreachable;

    const k_next = Node.initString(arena.allocator(), "next_page") catch unreachable;
    const v_next = Node.initNil(arena.allocator()) catch unreachable;
    const kv_next = Node.initKV(arena.allocator(), k_next, v_next) catch unreachable;

    const k_errors = Node.initString(arena.allocator(), "errors") catch unreachable;
    const v_errors = Node.initArray(arena.allocator(), @constCast(&[_]*Node{})) catch unreachable;
    const kv_errors = Node.initKV(arena.allocator(), k_errors, v_errors) catch unreachable;

    const stats_obj = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ kv_total, kv_next, kv_errors })) catch unreachable;
    const kv_stats = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "stats") catch unreachable, stats_obj) catch unreachable;

    // user1
    const u1_id_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "id") catch unreachable, Node.initNumber(arena.allocator(), "1") catch unreachable) catch unreachable;
    const u1_nm_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "name") catch unreachable, Node.initString(arena.allocator(), "Alice") catch unreachable) catch unreachable;
    const u1_act_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "active") catch unreachable, Node.initBoolean(arena.allocator(), true) catch unreachable) catch unreachable;
    const u1_roles = Node.initArray(arena.allocator(), @constCast(&[_]*Node{
        Node.initString(arena.allocator(), "admin") catch unreachable,
        Node.initString(arena.allocator(), "editor") catch unreachable,
    })) catch unreachable;
    const u1_roles_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "roles") catch unreachable, u1_roles) catch unreachable;
    const u1_last_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "last_login") catch unreachable, Node.initString(arena.allocator(), "2025-04-28T12:34:56Z") catch unreachable) catch unreachable;
    const u1_pref_arr = Node.initArray(arena.allocator(), @constCast(&[_]*Node{
        Node.initString(arena.allocator(), "email") catch unreachable,
        Node.initString(arena.allocator(), "sms") catch unreachable,
    })) catch unreachable;
    const u1_pref_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "preferences") catch unreachable, u1_pref_arr) catch unreachable;
    const u1_meta = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ u1_last_kv, u1_pref_kv })) catch unreachable;
    const u1_meta_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "metadata") catch unreachable, u1_meta) catch unreachable;
    const user1 = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ u1_id_kv, u1_nm_kv, u1_act_kv, u1_roles_kv, u1_meta_kv })) catch unreachable;

    // user2
    const u2_id_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "id") catch unreachable, Node.initNumber(arena.allocator(), "2") catch unreachable) catch unreachable;
    const u2_nm_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "name") catch unreachable, Node.initString(arena.allocator(), "Bob") catch unreachable) catch unreachable;
    const u2_act_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "active") catch unreachable, Node.initBoolean(arena.allocator(), false) catch unreachable) catch unreachable;
    const u2_roles = Node.initArray(arena.allocator(), @constCast(&[_]*Node{
        Node.initString(arena.allocator(), "viewer") catch unreachable,
    })) catch unreachable;
    const u2_roles_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "roles") catch unreachable, u2_roles) catch unreachable;
    const u2_last_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "last_login") catch unreachable, Node.initString(arena.allocator(), "2025-04-27T08:15:00Z") catch unreachable) catch unreachable;
    const u2_pref_arr = Node.initArray(arena.allocator(), @constCast(&[_]*Node{Node.initString(arena.allocator(), "push") catch unreachable})) catch unreachable;
    const u2_pref_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "preferences") catch unreachable, u2_pref_arr) catch unreachable;
    const u2_meta = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ u2_last_kv, u2_pref_kv })) catch unreachable;
    const u2_meta_kv = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "metadata") catch unreachable, u2_meta) catch unreachable;
    const user2 = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ u2_id_kv, u2_nm_kv, u2_act_kv, u2_roles_kv, u2_meta_kv })) catch unreachable;

    const users_arr = Node.initArray(arena.allocator(), @constCast(&[_]*Node{ user1, user2 })) catch unreachable;
    const kv_users = Node.initKV(arena.allocator(), Node.initString(arena.allocator(), "users") catch unreachable, users_arr) catch unreachable;

    const want = Node.initObject(arena.allocator(), @constCast(&[_]*Node{ kv_stats, kv_users })) catch unreachable;

    try std.testing.expect(nodesEqual(want, got));
}
