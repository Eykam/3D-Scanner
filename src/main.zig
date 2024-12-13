const std = @import("std");
const Queue = @import("./queue.zig").Queue;
const json = std.json;
const ArrayList = @import("std").ArrayList;
const net = std.net;
const fs = std.fs;
const mem = std.mem;
const expect = std.testing.expect;
const time = std.time;

const Connection = struct {
    conn: net.Server.Connection,
    start_time: i128,
};

const DataPoint = struct {
    distance: u32,
    horizontal: u16,
    vertical: u16,
};

const StatusTypes = enum {
    Offline,
    Initializing,
    Ready,
    Scanning,
    Paused,
    Done,
    Restarting,
};
const Status = struct { status: StatusTypes };

pub const ServeFileError = error{
    HeaderMalformed,
    MethodNotSupported,
    ProtoNotSupported,
    UnknownMimeType,
};

const Endpoints = enum {
    @"/data",
    @"/status",
};

const mimeTypes = .{
    .{ ".html", "text/html" },
    .{ ".css", "text/css" },
    .{ ".png", "image/png" },
    .{ ".jpg", "image/jpeg" },
    .{ ".gif", "image/gif" },
    .{ ".js", "application/javascript" },
};

const max_connections = 100; // Adjust as needed
const connection_timeout_ns = 10 * time.ns_per_s; // 10 seconds

var connections: std.ArrayList(Connection) = undefined;
var connections_mutex = std.Thread.Mutex{};

const StatusQueueType = Queue.FIFO(StatusTypes);
var status_queue: Queue.FIFO(StatusTypes) = undefined;

const SOCK_DGRAM = 2;

const server_addr = "172.18.243.58";
const server_port = 8035;
const tcp_port = 8036;

const client_addr = "192.168.1.219";
const client_port = 8035;

var buffer: [200]DataPoint = undefined;
var buffer_count: usize = 0;
var buffer_ready = false;
var curr_status = Status{ .status = StatusTypes.Offline };

pub fn main() !void {
    const spawn_config = std.Thread.SpawnConfig{
        .allocator = std.heap.page_allocator,
        .stack_size = 16 * 1024 * 1024, // You can adjust the stack size as needed
    };

    status_queue = StatusQueueType.init(std.heap.page_allocator);

    var tcp_thread = try std.Thread.spawn(spawn_config, startTcpServer, .{});
    var udp_receiving_thread = try std.Thread.spawn(spawn_config, startUdpReceivingServer, .{});
    var udp_transmitting_thread = try std.Thread.spawn(spawn_config, startUdpTrasmittingServer, .{});

    // Wait for both threads to finish (they won't in this case, so this will block)
    _ = tcp_thread.join();
    _ = udp_receiving_thread.join();
    _ = udp_transmitting_thread.join();
}

pub fn startTcpServer() !void {
    std.debug.print("Starting TCP server\n", .{});
    const self_addr = try net.Address.resolveIp("0.0.0.0", tcp_port);
    var listener = try self_addr.listen(.{ .reuse_address = true });
    std.debug.print("TCP server listening on {}\n", .{self_addr});

    connections = std.ArrayList(Connection).init(std.heap.page_allocator);
    defer connections.deinit();

    const cleanup_thread = try std.Thread.spawn(.{}, cleanupOldConnections, .{});
    cleanup_thread.detach();

    while (true) {
        const conn = listener.accept() catch |err| {
            std.debug.print("Error accepting connection: {}\n", .{err});
            continue;
        };

        std.debug.print("Accepted TCP connection from: {}\n", .{conn.address});

        try connections.append(.{
            .conn = conn,
            .start_time = time.nanoTimestamp(),
        });

        defer {
            connections_mutex.lock();
            for (connections.items, 0..) |connection, i| {
                if (connection.conn.stream.handle == conn.stream.handle) {
                    _ = connections.swapRemove(i);
                    break;
                }
            }
            connections_mutex.unlock();
            conn.stream.close();
        }

        var recv_buf: [4096]u8 = undefined;
        var recv_total: usize = 0;

        // Read the request
        while (conn.stream.read(recv_buf[recv_total..])) |recv_len| {
            recv_total += recv_len;
            if (mem.containsAtLeast(u8, recv_buf[0..recv_total], 1, "\r\n\r\n")) {
                break;
            }
        } else |read_err| {
            return read_err;
        }

        // Parse the HTTP request
        const recv_data = recv_buf[0..recv_total];
        const header = try parseHeader(recv_data);
        const path = try parsePath(header.requestLine);
        const pathToEnum = std.meta.stringToEnum(Endpoints, path);

        std.debug.print("method => {s}\npath => {s}\nenum => {?}\n", .{ header.method, path, pathToEnum });

        // Handle the /data endpoint
        if (pathToEnum == null) {
            try serveFileOr404(conn, path);
        } else {
            switch (pathToEnum.?) {
                .@"/data" => {
                    if (mem.eql(u8, header.method, "GET")) {
                        std.debug.print("Serving /data endpoint\n", .{});

                        const json_response = try serializeResponse();
                        defer std.heap.page_allocator.free(json_response);

                        const http_response =
                            "HTTP/1.1 200 OK\r\n" ++
                            "Content-Type: application/json\r\n" ++
                            "Content-Length: {}\r\n" ++
                            "Connection: close\r\n" ++
                            "\r\n";

                        _ = try conn.stream.writer().print(http_response, .{json_response.len});
                        _ = try conn.stream.writer().writeAll(json_response);
                    } else {
                        try sendMethodNotAllowed(conn);
                    }
                },
                .@"/status" => {
                    const allocator = std.heap.page_allocator;

                    if (mem.eql(u8, header.method, "GET")) {
                        std.debug.print("GET /status endpoint\n", .{});

                        var json_arr = ArrayList(u8).init(allocator);

                        try json.stringify(curr_status, .{}, json_arr.writer());

                        const http_response =
                            "HTTP/1.1 200 OK\r\n" ++
                            "Content-Type: application/json\r\n" ++
                            "Content-Length: {}\r\n" ++
                            "Connection: close\r\n" ++
                            "\r\n";

                        _ = try conn.stream.writer().print(http_response, .{json_arr.items.len});
                        _ = try conn.stream.writer().writeAll(json_arr.items);
                    } else if (mem.eql(u8, header.method, "POST")) {
                        std.debug.print("POST /status endpoint\n", .{});

                        // Extract the body from the received data
                        const body_start = mem.indexOf(u8, recv_data, "\r\n\r\n");
                        if (body_start == null) return error.InvalidRequest;
                        const body = recv_data[body_start.? + 4 ..];

                        const updated_status = try json.parseFromSlice(Status, allocator, body, .{});

                        std.debug.print("New status => {any}\n", .{updated_status.value.status});

                        if (curr_status.status != updated_status.value.status and curr_status.status != StatusTypes.Restarting) {
                            std.debug.print("============================\nAdding {any} to Queue", .{updated_status.value.status});
                            try status_queue.enqueue(updated_status.value.status);
                        }

                        // Send a response
                        const response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
                        _ = try conn.stream.writer().writeAll(response);
                    } else {
                        try sendMethodNotAllowed(conn);
                    }
                },
            }
        }
    }
}

fn cleanupOldConnections() void {
    while (true) {
        time.sleep(1 * time.ns_per_s); // Check every second

        connections_mutex.lock();
        defer connections_mutex.unlock();

        const now = time.nanoTimestamp();
        var i: usize = 0;
        while (i < connections.items.len) {
            if (now - connections.items[i].start_time > connection_timeout_ns) {
                std.debug.print("Closing old connection from: {}\n", .{connections.items[i].conn.address});
                connections.items[i].conn.stream.close();
                _ = connections.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
}

fn serializeResponse() ![]u8 {
    const allocator = std.heap.page_allocator;
    var json_arr = ArrayList(u8).init(allocator);

    if (buffer_ready) {
        try json_arr.appendSlice("[");

        for (buffer[0..buffer_count], 0..) |data, i| {
            if (i > 0) {
                try json_arr.appendSlice(","); // Add comma between objects
            }
            try json.stringify(data, .{}, json_arr.writer());
        }

        try json_arr.appendSlice("]"); // End the JSON array
        buffer_count = 0;
        buffer_ready = false;
    } else {
        std.debug.print("Buffer not ready! Current Count => {d}", .{buffer_count});
        try json_arr.appendSlice("[]");
    }

    // std.debug.print("json_arr {any}", .{json_arr.items});
    std.debug.print("Total # items: {d}", .{json_arr.items.len});
    return json_arr.items;
}

fn serveFileOr404(conn: anytype, path: []const u8) !void {
    const mime = mimeForPath(path);
    const buf = openLocalFile(path) catch |err| {
        if (err == error.FileNotFound) {
            _ = try conn.stream.writer().write(http404());
            return;
        } else {
            std.debug.print("Error file not found: {}", .{err});
            return;
        }
    };

    const httpHead =
        "HTTP/1.1 200 OK \r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: {s}\r\n" ++
        "Content-Length: {}\r\n" ++
        "\r\n";
    _ = try conn.stream.writer().print(httpHead, .{ mime, buf.len });
    _ = try conn.stream.writer().write(buf);
}

fn sendMethodNotAllowed(conn: anytype) !void {
    const response = "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n";
    _ = try conn.stream.writer().writeAll(response);
}

pub fn startUdpReceivingServer() !void {
    std.debug.print("Starting UDP server\n", .{});
    const parsed_address = try std.net.Address.parseIp4("0.0.0.0", server_port);

    const socket = try std.posix.socket(
        std.os.linux.AF.INET,
        std.os.linux.SOCK.DGRAM,
        0,
    );

    try std.posix.bind(socket, &parsed_address.any, parsed_address.getOsSockLen());
    std.debug.print("UDP server listening on {}\n", .{parsed_address});

    var src_addr: std.os.linux.sockaddr = undefined;
    var src_addr_len: std.os.linux.socklen_t = @sizeOf(std.os.linux.sockaddr);
    var recv_buf: [1024]u8 = undefined;

    while (true) {
        const recv_len = try std.posix.recvfrom(
            socket,
            &recv_buf,
            0,
            &src_addr,
            &src_addr_len,
        );

        if (recv_len == 8) {
            const base: u16 = 0x0000;
            const horizontal_steps: u16 = ((base | recv_buf[1]) << 8) | recv_buf[0];
            const vertical_steps: u16 = ((base | recv_buf[3]) << 8) | recv_buf[2];
            const distance: u32 = ((@as(u32, 0x00000000) | recv_buf[5]) << 24) | ((@as(u32, 0x00000000) | recv_buf[4]) << 16) | ((@as(u32, 0x00000000) | recv_buf[7]) << 8) | recv_buf[6];

            // std.debug.print("Received {d} bytes from {}: {x}\n", .{ recv_len, src_addr, recv_buf[0..recv_len] });
            // std.debug.print("Horizontal: {d}\nVertical: {d}\nDistance: {d}\n", .{ horizontal_steps, vertical_steps, distance });
            if (buffer_count < 200) {
                buffer[buffer_count] = DataPoint{
                    .distance = distance,
                    .horizontal = horizontal_steps,
                    .vertical = vertical_steps,
                };
                buffer_count += 1;
            }

            if (buffer_count >= 200) {
                // Buffer is full, handle sending data to frontend
                buffer_ready = true;
            }
        } else if (recv_len == 1) {
            const status: u8 = recv_buf[0];

            std.debug.print("======================\nReceived Status => {d} from scanner\n======================\n", .{status});
            curr_status = Status{ .status = @enumFromInt(status) };
            // try status_queue.enqueue(curr_status.status);
        }
    }
}

pub fn startUdpTrasmittingServer() !void {
    // const parsed_address = try std.net.Address.parseIp4("0.0.0.0", server_port);

    const socket = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        0,
    );

    // try std.posix.bind(socket, &parsed_address.any, parsed_address.getOsSockLen());
    std.debug.print("UDP Transmitting Server Started\n", .{});

    const dest_addr: std.posix.sockaddr = (try std.net.Address.parseIp4(client_addr, client_port)).any;
    const dest_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
    var send_buff: [1]u8 = undefined;

    const sleep_duration_ns = 250 * std.time.ns_per_ms; // 100 milliseconds in nanoseconds

    while (true) {
        const queued_status = status_queue.dequeue();

        if (queued_status) |status| {
            send_buff[0] = @intFromEnum(status);
            std.debug.print("==============================\nSending Packet to Scanner => {any}\n", .{send_buff});
            _ = try std.posix.sendto(socket, &send_buff, 0, &dest_addr, dest_addr_len);
            curr_status = Status{ .status = status };
        } else {
            send_buff[0] = 255;
            std.debug.print("==============================\nSending Keepalive to Scanner => {any}\n", .{send_buff});
            _ = try std.posix.sendto(socket, &send_buff, 0, &dest_addr, dest_addr_len);
        }

        // Sleep for 100 milliseconds
        std.time.sleep(sleep_duration_ns);
    }
}

pub fn mimeForPath(path: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    inline for (mimeTypes) |kv| {
        if (mem.eql(u8, extension, kv[0])) {
            return kv[1];
        }
    }
    return "application/octet-stream";
}

pub fn http404() []const u8 {
    return "HTTP/1.1 404 NOT FOUND \r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: text/html; charset=utf8\r\n" ++
        "Content-Length: 9\r\n" ++
        "\r\n" ++
        "NOT FOUND";
}

pub fn openLocalFile(path: []const u8) ![]u8 {
    const localPath = path[1..];
    const file = fs.cwd().openFile(localPath, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("File not found: {s}\n", .{localPath});
            return error.FileNotFound;
        },
        else => return err,
    };
    defer file.close();

    std.debug.print("file: {}\n", .{file});
    const memory = std.heap.page_allocator;
    const maxSize = std.math.maxInt(usize);
    return try file.readToEndAlloc(memory, maxSize);
}

pub fn parsePath(requestLine: []const u8) ![]const u8 {
    var requestLineIter = mem.tokenizeScalar(u8, requestLine, ' ');
    const method = requestLineIter.next().?;
    if (!mem.eql(u8, method, "GET") and !mem.eql(u8, method, "POST")) return ServeFileError.MethodNotSupported;
    const path = requestLineIter.next().?;
    if (path.len <= 0) return error.NoPath;
    const proto = requestLineIter.next().?;
    if (!mem.eql(u8, proto, "HTTP/1.1")) return ServeFileError.ProtoNotSupported;
    if (mem.eql(u8, path, "/")) {
        return "/index.html";
    }
    return path;
}

const HeaderNames = enum {
    Host,
    @"User-Agent",
};

const HTTPHeader = struct {
    method: []const u8,
    requestLine: []const u8,
    host: []const u8,
    userAgent: []const u8,

    pub fn print(self: HTTPHeader) void {
        std.debug.print("{s} - {s} - {s}\n", .{
            self.method,
            self.requestLine,
            self.host,
        });
    }
};

pub fn parseHeader(header: []const u8) !HTTPHeader {
    var headerStruct = HTTPHeader{
        .method = undefined,
        .requestLine = undefined,
        .host = undefined,
        .userAgent = undefined,
    };
    var headerIter = mem.tokenizeSequence(u8, header, "\r\n");

    // Parse the request line
    const requestLine = headerIter.next() orelse return ServeFileError.HeaderMalformed;
    headerStruct.requestLine = requestLine;

    // Extract the method from the request line
    var requestLineParts = mem.splitAny(u8, requestLine, " ");
    headerStruct.method = requestLineParts.next() orelse return ServeFileError.HeaderMalformed;

    // Parse the rest of the headers
    while (headerIter.next()) |line| {
        const nameSlice = mem.sliceTo(line, ':');
        if (nameSlice.len == line.len) return ServeFileError.HeaderMalformed;
        const headerName = std.meta.stringToEnum(HeaderNames, nameSlice) orelse continue;
        const headerValue = mem.trimLeft(u8, line[nameSlice.len + 1 ..], " ");
        switch (headerName) {
            .Host => headerStruct.host = headerValue,
            .@"User-Agent" => headerStruct.userAgent = headerValue,
        }
    }
    return headerStruct;
}
