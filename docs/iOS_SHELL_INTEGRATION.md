# iOS Shell Integration Guide

## Overview

The iOS terminal MVP uses a pipe-based PTY (IOSPty) instead of a true POSIX PTY due to iOS sandbox restrictions. This document explains shell integration options.

## How It Works

The architecture works as follows:
```
Swift UI → libghostty C API → Zig Terminal Engine → IOSPty (pipes) → Shell Process
```

The existing `Command.zig` uses `fork()` + `exec()` which IS allowed on iOS for regular apps (but not extensions or daemons).

## Shell Options for iOS

### Option 1: Local Shell (Requires iOS-system or bundled shell)

For a fully local experience, you need a shell executable. Options:

#### A. Use ios_system Framework (Recommended for App Store)
- **What**: Open-source framework providing POSIX commands as library calls
- **Used by**: a-shell, other App Store terminals
- **GitHub**: https://github.com/holzschu/ios_system
- **Pros**: App Store compatible, no external processes
- **Cons**: Not a true shell, limited to bundled commands

**Integration**:
```swift
import ios_system

// Instead of fork/exec, use ios_system's functions
ios_setMiniRoot(Bundle.main.resourcePath)
ios_system("ls -la") // Runs ls command in-process
```

#### B. Bundle a Shell Binary
- **What**: Include a compiled shell (dash, bash subset) in app bundle
- **Requires**: Building shell for iOS, may need jailbreak
- **Pros**: True shell experience
- **Cons**: App Store review risk, larger app size

#### C. Jailbroken Device
- On jailbroken iOS, `/bin/sh` and standard shells are available
- Works out-of-the-box with current implementation
- Not viable for App Store distribution

### Option 2: SSH to Remote Host (Current MVP Approach)

Connect to a remote server via SSH for full shell access:

**Pros**:
- Full POSIX shell on remote server
- App Store compatible
- Works on all iOS devices

**Cons**:
- Requires network connection
- Requires SSH server access
- Latency

**Implementation**: Add libssh2 or NMSSH integration (future work).

### Option 3: Hybrid Approach

- **Default**: iOS local commands via ios_system
- **Optional**: SSH for advanced users
- **Best of both worlds**

## Current Implementation Status

### ✅ What Works Now
- IOSPty (pipe-based PTY) ✅
- Process spawning via fork/exec ✅
- Terminal I/O pipeline ✅
- Input/output redirection ✅

### ⏳ What's Needed for Full Shell
- Choose shell integration method
- Configure shell path in Settings
- Add ios_system framework OR
- Add SSH client library

## Configuration

The shell is configured via the existing Ghostty config:

```conf
# For local shell (if available)
shell = /path/to/shell

# Or use explicit command
command = /bin/sh

# Environment variables
env = PATH=/usr/local/bin:/usr/bin:/bin
```

On iOS, you'll set this in the Settings UI.

## Testing Scenarios

### Without Shell
1. App launches ✅
2. Terminal renders ✅
3. Keyboard input works ✅
4. No shell process (expected)

### With ios_system
1. Bundle ios_system framework
2. Integrate command execution
3. Test basic commands (ls, cd, echo)

### With SSH
1. Add libssh2
2. Implement connection UI
3. Connect to remote host
4. Full shell experience

## Recommended Next Steps

### For MVP (Immediate)
1. ✅ Complete terminal input/output
2. Add Settings UI to configure shell
3. Add "No Shell Configured" placeholder screen
4. Document shell options for users

### For v1.0 (Near-term)
1. Integrate ios_system framework
2. Bundle common UNIX commands
3. Provide basic local shell experience

### For v2.0 (Future)
1. Add SSH client support
2. Connection manager UI
3. Saved SSH profiles
4. Both local AND remote options

## Technical Notes

### Why Not posix_spawn?
The existing code uses `fork()` + `exec()` because:
- Needs `pre_exec` callback for PTY setup
- `posix_spawn` doesn't support pre-exec on all platforms
- `fork()` is allowed on iOS for apps

### iOS Sandbox Restrictions
- No true PTY (fixed with IOSPty pipes) ✅
- Limited filesystem access (use app sandbox)
- No `/bin/sh` on stock devices (use ios_system or SSH)

### Performance
- Local ios_system: ~1ms command latency
- SSH: 20-100ms latency (network dependent)
- Fork/exec overhead: ~2-5ms (negligible)

## Resources

- **ios_system**: https://github.com/holzschu/ios_system
- **a-shell source**: https://github.com/holzschu/a-shell
- **libssh2**: https://www.libssh2.org/
- **NMSSH**: https://github.com/NMSSH/NMSSH

## Example: ios_system Integration

```swift
// In your shell launcher:
import ios_system

class IOSSystemShell {
    func start(command: String, env: [String: String]) {
        // Setup iOS system
        ios_setMiniRoot(Bundle.main.resourcePath)

        // Set environment
        for (key, value) in env {
            setenv(key, value, 1)
        }

        // Setup I/O redirection to our pipes
        ios_setStreams(stdin_pipe, stdout_pipe, stderr_pipe)

        // Run command in iOS system
        ios_system(command)
    }
}
```

This approach is how a-shell works and is App Store approved.
