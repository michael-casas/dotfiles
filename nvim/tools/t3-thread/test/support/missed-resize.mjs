// Deliberately drop SIGWINCH's public stream event (not its dimension update)
// so action 9 must repair stale React state. Test process only.
const emit = process.stdout.emit;
process.stdout.emit = function(event, ...args) {
  return event === "resize" ? false : emit.call(this, event, ...args);
};
