const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const assert = std.debug.assert;

const log = std.log.scoped(.ios_pty);

/// iOS PTY implementation using pipes instead of real PTY.
///
/// iOS doesn't support POSIX PTY due to sandbox restrictions, so we use
/// pipes for stdin/stdout/stderr communication. This approach is similar
/// to what a-shell and other iOS terminal apps use.
///
/// Limitations compared to real PTY:
/// - No job control (no signals like SIGWINCH, SIGTSTP, etc.)
/// - No terminal attributes (termios)
/// - Limited process control
/// - No controlling terminal
///
/// Despite these limitations, this provides a functional terminal experience
/// for most use cases.
pub const IOSPty = struct {
    pub const Error = OpenError || GetModeError || SetSizeError || ChildPreExecError;

    pub const Fd = posix.fd_t;

    /// Master file descriptor - used for both reading and writing
    /// (for compatibility with PosixPty interface)
    master: Fd,

    /// Slave file descriptor - child process reads stdin from this
    /// (for compatibility with PosixPty interface)
    slave: Fd,

    /// File descriptor for writing to the shell process (master writes to child's stdin)
    write_fd: Fd,

    /// File descriptor for the child process to write stdout/stderr
    child_write_fd: Fd,

    /// Current size - stored here since we can't query it from a real PTY
    current_size: @import("../pty.zig").winsize,

    /// Process ID of the child shell (if launched)
    pid: ?std.posix.pid_t = null,

    pub const OpenError = error{
        CreatePipeFailed,
        SetNonblockFailed,
        SetCloexecFailed,
    };

    /// Open a new pseudo-PTY with the given initial size.
    ///
    /// This creates two pipes:
    /// 1. Master writes -> Child reads (stdin)
    /// 2. Child writes -> Master reads (stdout/stderr)
    pub fn open(size: @import("../pty.zig").winsize) OpenError!IOSPty {
        // Create pipe for stdin (master -> child)
        var stdin_pipe: [2]Fd = undefined;
        if (posix.system.pipe(&stdin_pipe) != 0) {
            log.err("failed to create stdin pipe", .{});
            return error.CreatePipeFailed;
        }
        errdefer {
            _ = posix.system.close(stdin_pipe[0]);
            _ = posix.system.close(stdin_pipe[1]);
        }

        // Create pipe for stdout/stderr (child -> master)
        var stdout_pipe: [2]Fd = undefined;
        if (posix.system.pipe(&stdout_pipe) != 0) {
            log.err("failed to create stdout pipe", .{});
            return error.CreatePipeFailed;
        }
        errdefer {
            _ = posix.system.close(stdout_pipe[0]);
            _ = posix.system.close(stdout_pipe[1]);
        }

        // Set non-blocking mode on master fds for async I/O
        inline for ([_]Fd{ stdin_pipe[1], stdout_pipe[0] }) |fd| {
            const flags = posix.fcntl(fd, posix.F.GETFL, 0) catch {
                log.err("failed to get flags for fd {d}", .{fd});
                return error.SetNonblockFailed;
            };

            _ = posix.fcntl(fd, posix.F.SETFL, flags | posix.O.NONBLOCK) catch {
                log.err("failed to set non-blocking on fd {d}", .{fd});
                return error.SetNonblockFailed;
            };
        }

        // Set CLOEXEC on master fds so they don't leak to child
        inline for ([_]Fd{ stdin_pipe[1], stdout_pipe[0] }) |fd| {
            const flags = posix.fcntl(fd, posix.F.GETFD, 0) catch {
                log.err("failed to get fd flags for fd {d}", .{fd});
                return error.SetCloexecFailed;
            };

            _ = posix.fcntl(fd, posix.F.SETFD, flags | posix.FD_CLOEXEC) catch {
                log.err("failed to set CLOEXEC on fd {d}", .{fd});
                return error.SetCloexecFailed;
            };
        }

        log.debug("created iOS PTY with pipes: stdin=[{d},{d}] stdout=[{d},{d}]", .{
            stdin_pipe[0],
            stdin_pipe[1],
            stdout_pipe[0],
            stdout_pipe[1],
        });

        return .{
            // Master side (terminal emulator reads from stdout_pipe)
            .master = stdout_pipe[0], // Read from child's stdout

            // Slave side (shell process reads from stdin_pipe)
            .slave = stdin_pipe[0], // Child reads from stdin

            // Additional file descriptors for write operations
            .write_fd = stdin_pipe[1], // Write to child's stdin
            .child_write_fd = stdout_pipe[1], // Child writes to stdout

            .current_size = size,
        };
    }

    pub fn deinit(self: *IOSPty) void {
        // Close master fds
        _ = posix.system.close(self.master);
        _ = posix.system.close(self.write_fd);

        // Close slave fds if they haven't been closed yet
        // (they should be closed by childPreExec, but just in case)
        _ = posix.system.close(self.slave);
        _ = posix.system.close(self.child_write_fd);

        log.debug("closed iOS PTY", .{});
        self.* = undefined;
    }

    pub const GetModeError = error{NotSupported};

    /// Get terminal mode. Not supported on iOS PTY.
    pub fn getMode(self: IOSPty) GetModeError!@import("../pty.zig").Mode {
        _ = self;
        // We can't get real terminal modes without a PTY, but we return
        // sensible defaults for a terminal
        return .{
            .canonical = false,
            .echo = false,
        };
    }

    pub const GetSizeError = error{};

    /// Return the current size of the PTY.
    pub fn getSize(self: IOSPty) GetSizeError!@import("../pty.zig").winsize {
        return self.current_size;
    }

    pub const SetSizeError = error{};

    /// Set the size of the PTY.
    ///
    /// Since we don't have a real PTY, we can't send SIGWINCH to the child.
    /// We just store the size and hope the application checks it periodically
    /// or that the shell integration handles it.
    pub fn setSize(self: *IOSPty, size: @import("../pty.zig").winsize) SetSizeError!void {
        log.debug("setting PTY size to {d}x{d}", .{ size.ws_col, size.ws_row });
        self.current_size = size;

        // TODO: If we have a pid, we could try to send a custom signal or
        // write a size change notification to the pipe. For now, we rely on
        // shell integration or periodic size checks.
    }

    pub const ChildPreExecError = error{
        DupFailed,
        CloseFailed,
    };

    /// Prepare the child process for exec.
    ///
    /// This should be called after fork() but before exec() in the child process.
    /// It sets up stdin/stdout/stderr to point to our pipes.
    pub fn childPreExec(self: IOSPty) ChildPreExecError!void {
        // Redirect stdin to our pipe (slave = child's stdin)
        if (posix.system.dup2(self.slave, posix.STDIN_FILENO) < 0) {
            log.err("failed to dup2 stdin", .{});
            return error.DupFailed;
        }

        // Redirect stdout to our pipe
        if (posix.system.dup2(self.child_write_fd, posix.STDOUT_FILENO) < 0) {
            log.err("failed to dup2 stdout", .{});
            return error.DupFailed;
        }

        // Redirect stderr to the same pipe as stdout
        if (posix.system.dup2(self.child_write_fd, posix.STDERR_FILENO) < 0) {
            log.err("failed to dup2 stderr", .{});
            return error.DupFailed;
        }

        // Close the original pipe fds since we've duplicated them
        _ = posix.system.close(self.slave);
        _ = posix.system.close(self.child_write_fd);

        // Close the master fds (they should already be CLOEXEC, but be explicit)
        _ = posix.system.close(self.write_fd);
        _ = posix.system.close(self.master);

        log.debug("child pre-exec setup complete", .{});
    }

};

test "ios pty creation and cleanup" {
    const testing = std.testing;
    const winsize = @import("../pty.zig").winsize;

    var ws: winsize = .{
        .ws_row = 24,
        .ws_col = 80,
        .ws_xpixel = 800,
        .ws_ypixel = 600,
    };

    var pty = try IOSPty.open(ws);
    defer pty.deinit();

    // Verify size
    const size = try pty.getSize();
    try testing.expectEqual(ws.ws_row, size.ws_row);
    try testing.expectEqual(ws.ws_col, size.ws_col);

    // Verify we can change size
    ws.ws_row = 40;
    ws.ws_col = 120;
    try pty.setSize(ws);

    const new_size = try pty.getSize();
    try testing.expectEqual(ws.ws_row, new_size.ws_row);
    try testing.expectEqual(ws.ws_col, new_size.ws_col);
}

test "ios pty write and read" {
    const testing = std.testing;
    const winsize = @import("../pty.zig").winsize;

    var pty = try IOSPty.open(.{});
    defer pty.deinit();

    // Write some data to the write fd (master writes to child's stdin)
    const test_data = "Hello, iOS PTY!";
    const written = try posix.write(pty.write_fd, test_data);
    try testing.expectEqual(test_data.len, written);

    // Read from the child's perspective (slave reads stdin)
    var buf: [256]u8 = undefined;
    const read = try posix.read(pty.slave, &buf);
    try testing.expectEqual(test_data.len, read);
    try testing.expectEqualStrings(test_data, buf[0..read]);

    // Now write from child and read from master
    const response = "Response from shell";
    const written2 = try posix.write(pty.child_write_fd, response);
    try testing.expectEqual(response.len, written2);

    const read2 = try posix.read(pty.master, &buf);
    try testing.expectEqual(response.len, read2);
    try testing.expectEqualStrings(response, buf[0..read2]);
}
