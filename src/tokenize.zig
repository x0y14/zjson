const std = @import("std");

pub const tokenkind = enum {
    illegal,
    eof,
    whitespace,
    string,

    lcb, // {
    rcb, // }
    colon, // :
};

pub const token = struct {
    kind: tokenkind,
    raw: []const u8,
    next: *token,

    // アロケータを受け取るinit関数
    fn init(allocator: std.mem.Allocator, kind: tokenkind, raw: []const u8) !*token {
        const tok_ptr = allocator.create(token) catch return error.OutOfMemory;
        tok_ptr.* = .{ .kind = kind, .raw = raw, .next = undefined };
        return tok_ptr;
    }

    // フィールドごとの比較を行う関数を追加
    fn eql(self: @This(), other: @This()) bool {
        return self.kind == other.kind and std.mem.eql(u8, self.raw, other.raw);
    }
};

pub const TokenizeError = error{
    UnexpectedChar,
};

var chars: []const u8 = "";
var pos: u8 = 0;
var curt: *token = undefined;

fn consumeWhiteSpace(allocator: std.mem.Allocator) *token {
    var list = std.ArrayList(u8).init(allocator);
    ws_loop: while (chars.len > pos) {
        switch (chars[pos]) {
            ' ' => {
                list.append(' ') catch unreachable;
                pos += 1;
            },
            else => {
                break :ws_loop;
            },
        }
    }
    const owned_slice = list.toOwnedSlice() catch unreachable;
    const ws_ptr = token.init(allocator, tokenkind.whitespace, owned_slice) catch unreachable;
    return ws_ptr;
}

fn consumeString(allocator: std.mem.Allocator) *token {
    var list = std.ArrayList(u8).init(allocator);
    pos += 1; // consume opening double-quo
    str_loop: while (chars.len > pos) {
        switch (chars[pos]) {
            '"' => {
                pos += 1; // consume closing double-quo
                break :str_loop;
            },
            else => {
                list.append(chars[pos]) catch unreachable;
                pos += 1;
            },
        }
    }
    const owned_slice = list.toOwnedSlice() catch unreachable;
    const str_ptr = token.init(allocator, tokenkind.string, owned_slice) catch unreachable;
    return str_ptr;
}

fn consumeSymbol(allocator: std.mem.Allocator) TokenizeError!*token {
    switch (chars[pos]) {
        '{' => {
            pos += 1;
            return token.init(allocator, tokenkind.lcb, &.{}) catch unreachable;
        },
        '}' => {
            pos += 1;
            return token.init(allocator, tokenkind.rcb, &.{}) catch unreachable;
        },
        ':' => {
            pos += 1;
            return token.init(allocator, tokenkind.colon, &.{}) catch unreachable;
        },
        else => {
            pos += 1;
            return TokenizeError.UnexpectedChar;
        },
    }
}

pub fn tokenize(allocator: std.mem.Allocator, user_input: []const u8) TokenizeError!*token {
    chars = user_input;
    pos = 0;
    const head_ptr = token.init(allocator, tokenkind.illegal, &.{}) catch unreachable;
    curt = head_ptr;

    while (chars.len > pos) {
        switch (chars[pos]) {
            ' ' => {
                const tok = consumeWhiteSpace(allocator);
                curt.next = tok;
                curt = curt.next;
            },
            '"' => {
                const tok = consumeString(allocator);
                curt.next = tok;
                curt = curt.next;
            },
            '{', '}', ':' => {
                const tok = consumeSymbol(allocator) catch unreachable;
                curt.next = tok;
                curt = curt.next;
            },
            else => {
                return TokenizeError.UnexpectedChar;
            },
        }
    }

    const eof_ptr = token.init(allocator, tokenkind.eof, &.{}) catch unreachable;
    curt.next = eof_ptr;
    curt = curt.next;
    return head_ptr.next;
}

test "ws" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const expect_ws_ptr = token.init(arena.allocator(), tokenkind.whitespace, "   ") catch unreachable;
    const expect_eof_ptr = token.init(arena.allocator(), tokenkind.eof, &.{}) catch unreachable;
    expect_ws_ptr.next = expect_eof_ptr;

    const actual = tokenize(arena.allocator(), "   ") catch unreachable;

    // eql関数を使用して比較
    try std.testing.expect(expect_ws_ptr.*.eql(actual.*));
    try std.testing.expect(expect_ws_ptr.next.*.eql(actual.next.*));
}

test "str" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const expect_str_ptr = token.init(arena.allocator(), tokenkind.string, "hello") catch unreachable;
    const expect_eof_ptr = token.init(arena.allocator(), tokenkind.eof, &.{}) catch unreachable;
    expect_str_ptr.next = expect_eof_ptr;

    const actual = tokenize(arena.allocator(), "\"hello\"") catch unreachable;

    // eql関数を使用して比較
    try std.testing.expect(expect_str_ptr.*.eql(actual.*));
    try std.testing.expect(expect_str_ptr.next.*.eql(actual.next.*));
}

test "ws-str-ws" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const expect_ws_1_ptr = token.init(arena.allocator(), tokenkind.whitespace, " ") catch unreachable;
    const expect_str_ptr = token.init(arena.allocator(), tokenkind.string, "hello") catch unreachable;
    const expect_ws_2_ptr = token.init(arena.allocator(), tokenkind.whitespace, " ") catch unreachable;
    const expect_eof_ptr = token.init(arena.allocator(), tokenkind.eof, &.{}) catch unreachable;
    expect_ws_1_ptr.next = expect_str_ptr;
    expect_str_ptr.next = expect_ws_2_ptr;
    expect_ws_2_ptr.next = expect_eof_ptr;

    const actual = tokenize(arena.allocator(), " \"hello\" ") catch unreachable;

    try std.testing.expect(expect_ws_1_ptr.*.eql(actual.*));
    try std.testing.expect(expect_str_ptr.*.eql(actual.next.*));
    try std.testing.expect(expect_ws_2_ptr.*.eql(actual.next.next.*));
    try std.testing.expect(expect_eof_ptr.*.eql(actual.next.next.next.*));
}

test "symbol" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const expect_ws_ptr = token.init(arena.allocator(), tokenkind.lcb, &.{}) catch unreachable;
    const expect_eof_ptr = token.init(arena.allocator(), tokenkind.eof, &.{}) catch unreachable;
    expect_ws_ptr.next = expect_eof_ptr;

    const actual = tokenize(arena.allocator(), "{") catch unreachable;

    // eql関数を使用して比較
    try std.testing.expect(expect_ws_ptr.*.eql(actual.*));
    try std.testing.expect(expect_ws_ptr.next.*.eql(actual.next.*));
}

test "string-kv" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // { "key": "value" }
    const exp_lcb = token.init(arena.allocator(), tokenkind.lcb, &.{}) catch unreachable;
    const exp_w1 = token.init(arena.allocator(), tokenkind.whitespace, " ") catch unreachable;
    const exp_key = token.init(arena.allocator(), tokenkind.string, "key") catch unreachable;
    const exp_colon = token.init(arena.allocator(), tokenkind.colon, &.{}) catch unreachable;
    const exp_w2 = token.init(arena.allocator(), tokenkind.whitespace, " ") catch unreachable;
    const exp_val = token.init(arena.allocator(), tokenkind.string, "value") catch unreachable;
    const exp_w3 = token.init(arena.allocator(), tokenkind.whitespace, " ") catch unreachable;
    const exp_rcb = token.init(arena.allocator(), tokenkind.rcb, &.{}) catch unreachable;
    const exp_eof = token.init(arena.allocator(), tokenkind.eof, &.{}) catch unreachable;
    exp_lcb.next = exp_w1;
    exp_w1.next = exp_key;
    exp_key.next = exp_colon;
    exp_colon.next = exp_w2;
    exp_w2.next = exp_val;
    exp_val.next = exp_w3;
    exp_w3.next = exp_rcb;
    exp_rcb.next = exp_eof;

    const actual = tokenize(arena.allocator(), "{ \"key\": \"value\" }") catch unreachable;

    try std.testing.expect(exp_lcb.*.eql(actual.*));
    try std.testing.expect(exp_w1.*.eql(actual.next.*));
    try std.testing.expect(exp_key.*.eql(actual.next.next.*));
    try std.testing.expect(exp_colon.*.eql(actual.next.next.next.*));
    try std.testing.expect(exp_w2.*.eql(actual.next.next.next.next.*));
    try std.testing.expect(exp_val.*.eql(actual.next.next.next.next.next.*));
    try std.testing.expect(exp_w3.*.eql(actual.next.next.next.next.next.next.*));
    try std.testing.expect(exp_rcb.*.eql(actual.next.next.next.next.next.next.next.*));
    try std.testing.expect(exp_eof.*.eql(actual.next.next.next.next.next.next.next.next.*));
}
