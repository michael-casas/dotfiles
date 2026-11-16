// world-cursor: hides the macOS cursor while the World mod turns its camera.
//
//   world-cursor hold      remember the cursor position, hide the cursor, block:
//                            SIGUSR1                 -> warp back to that spot
//                            TERM / INT / HUP / 120 s -> warp back, show, exit 0
//   world-cursor release   tell the running holder to exit (exit 0 if none)
//   world-cursor recenter  send SIGUSR1 to the running holder (exit 0 if none)
//   world-cursor visible   debug: print whether the cursor is visible
//
// A background process can only hide the cursor after setting the private
// "SetsCursorInBackground" property on its WindowServer connection. The hide
// belongs to that connection, so the OS shows the cursor again when the process
// dies for any reason, SIGKILL included.

import CoreGraphics
import Darwin

let maxHoldSeconds = 120

let pidPath: String = {
    var dir = getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp"
    if !dir.hasSuffix("/") { dir += "/" }
    return dir + "world-cursor.pid"
}()

func fail(_ message: String) -> Never {
    fputs("world-cursor: \(message)\n", stderr)
    exit(1)
}

// MARK: pid file

func readPidFile() -> pid_t? {
    guard let f = fopen(pidPath, "r") else { return nil }
    defer { fclose(f) }
    var line = [CChar](repeating: 0, count: 32)
    guard fgets(&line, Int32(line.count), f) != nil else { return nil }
    let pid = pid_t(atoi(line))
    return pid > 0 ? pid : nil
}

/// The pid of a live holder other than us, if the pid file names one.
func holderPid() -> pid_t? {
    guard let pid = readPidFile(), pid != getpid(), kill(pid, 0) == 0 else { return nil }
    // Guard against pid reuse: only trust a process that is still world-cursor.
    var name = [CChar](repeating: 0, count: 256)
    guard proc_name(pid, &name, UInt32(name.count)) > 0,
          String(cString: name).hasPrefix("world-cursor") else { return nil }
    return pid
}

func writePidFile() {
    let tmp = pidPath + ".\(getpid())"
    guard let f = fopen(tmp, "w") else { return }
    fputs("\(getpid())\n", f)
    fclose(f)
    rename(tmp, pidPath)
}

func removePidFileIfOurs() {
    if readPidFile() == getpid() { unlink(pidPath) }
}

/// Signals the running holder; with `waitForExit`, polls up to 1 s for it to go.
func signalHolder(_ sig: Int32, waitForExit: Bool) {
    guard let pid = holderPid() else { return }
    kill(pid, sig)
    guard waitForExit else { return }
    for _ in 0..<200 where kill(pid, 0) == 0 { usleep(5_000) }
}

// MARK: private CGS call

typealias CGSConnectionID = Int32
typealias DefaultConnectionFn = @convention(c) () -> CGSConnectionID
typealias SetConnectionPropertyFn =
    @convention(c) (CGSConnectionID, CGSConnectionID, CFString, CFTypeRef) -> Int32

func lookup<T>(_ names: [String], as _: T.Type) -> T? {
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    for name in names {
        if let sym = dlsym(rtldDefault, name) { return unsafeBitCast(sym, to: T.self) }
    }
    return nil
}

func allowCursorChangesInBackground() {
    guard
        let defaultConnection = lookup(["_CGSDefaultConnection", "SLSMainConnectionID"],
                                       as: DefaultConnectionFn.self),
        let setProperty = lookup(["CGSSetConnectionProperty", "SLSSetConnectionProperty"],
                                 as: SetConnectionPropertyFn.self)
    else { fail("private CGS symbols not found; cannot hide the cursor from the background") }
    let cid = defaultConnection()
    let err = setProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    if err != 0 { fail("CGSSetConnectionProperty failed (\(err))") }
}

// MARK: cursor

/// CGCursorIsVisible is deprecated but still exported; Swift won't call it directly.
let cursorIsVisible: () -> Bool = {
    typealias Fn = @convention(c) () -> UInt32
    guard let fn = lookup(["CGCursorIsVisible"], as: Fn.self) else { return { true } }
    return { fn() != 0 }
}()

func warp(to p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    // Re-associating right away cancels the post-warp input suppression.
    CGAssociateMouseAndMouseCursorPosition(1)
}

func showCursor() {
    let display = CGMainDisplayID()
    for _ in 0..<16 where !cursorIsVisible() { CGDisplayShowCursor(display) }
}

// MARK: hold

func hold() -> Never {
    // Let a previous holder warp back and exit before we record the position.
    signalHolder(SIGTERM, waitForExit: true)

    let kq = kqueue()
    guard kq >= 0 else { fail("kqueue failed") }
    var changes = [SIGUSR1, SIGTERM, SIGINT, SIGHUP].map { sig -> kevent in
        signal(sig, SIG_IGN) // kqueue still reports ignored signals
        return kevent(ident: UInt(sig), filter: Int16(EVFILT_SIGNAL),
                      flags: UInt16(EV_ADD), fflags: 0, data: 0, udata: nil)
    }
    guard kevent(kq, &changes, Int32(changes.count), nil, 0, nil) == 0 else {
        fail("kevent registration failed")
    }

    let home = CGEvent(source: nil)?.location ?? .zero
    writePidFile()
    allowCursorChangesInBackground()
    CGDisplayHideCursor(CGMainDisplayID())

    func finish() -> Never {
        warp(to: home)
        showCursor()
        removePidFileIfOurs()
        exit(0)
    }

    var start = timespec()
    clock_gettime(CLOCK_MONOTONIC, &start)
    let end = start.tv_sec + maxHoldSeconds

    while true {
        var now = timespec()
        clock_gettime(CLOCK_MONOTONIC, &now)
        let left = end - now.tv_sec
        if left <= 0 { finish() }
        var timeout = timespec(tv_sec: left, tv_nsec: 0)
        var event = kevent()
        let n = kevent(kq, nil, 0, &event, 1, &timeout)
        if n < 0 && errno == EINTR { continue }
        if n <= 0 { finish() }
        if Int32(event.ident) == SIGUSR1 { warp(to: home) } else { finish() }
    }
}

// MARK: main

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "hold": hold()
case "release": signalHolder(SIGTERM, waitForExit: false)
case "recenter": signalHolder(SIGUSR1, waitForExit: false)
case "visible": print(cursorIsVisible() ? "true" : "false")
default:
    fputs("usage: world-cursor hold|release|recenter|visible\n", stderr)
    exit(2)
}
exit(0)
