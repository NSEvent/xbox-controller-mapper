// Makes ChatGPT's node-hid discovery see a synthetic Work Louder Codex Micro.
// HID reports are exchanged with ControllerKeys over a local Unix socket.
// Derived from mpociot/codex-micro-stream-deck-emulator; see the bundled notice.

const net = require("node:net");
const fs = require("node:fs");
const { EventEmitter } = require("node:events");

const REPORT_SIZE = 64;
const FAKE_PATH = "controllerkeys-codex-micro-virtual";
const FAKE_DESCRIPTOR = Object.freeze({
  vendorId: 0x303a,
  productId: 0x8360,
  path: FAKE_PATH,
  serialNumber: "controllerkeys-codex-micro",
  manufacturer: "Work Louder",
  product: "Codex Micro",
  release: 0x0100,
  interface: 0,
  usagePage: 0xff00,
  usage: 0x01,
});

function defaultSocketPath() {
  return process.env.CODEX_MICRO_SOCKET || "/tmp/controllerkeys-codex-micro.sock";
}

let logStream = null;
function log(message) {
  const file = process.env.CODEX_MICRO_SHIM_LOG;
  if (!file) return;
  try {
    if (!logStream) logStream = fs.createWriteStream(file, { flags: "a" });
    logStream.write(`[${new Date().toISOString()}] ${message}\n`);
  } catch {
    // Diagnostics are best-effort.
  }
}

function toFrame(data) {
  const input = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (input.length === REPORT_SIZE) return input;
  const frame = Buffer.alloc(REPORT_SIZE);
  input.copy(frame, 0, 0, Math.min(input.length, REPORT_SIZE));
  return frame;
}

class FakeHIDAsync extends EventEmitter {
  constructor(socketPath) {
    super();
    this.socketPath = socketPath;
    this.socket = null;
    this.connected = false;
    this.receiveBuffer = Buffer.alloc(0);
    this.pendingFrames = [];
    this.connect();
  }

  connect() {
    const socket = net.createConnection(this.socketPath);
    this.socket = socket;
    socket.on("connect", () => {
      this.connected = true;
      log(`connected to ControllerKeys at ${this.socketPath}`);
      for (const frame of this.pendingFrames) socket.write(frame);
      this.pendingFrames = [];
    });
    socket.on("data", (chunk) => this.onData(chunk));
    socket.on("error", (error) => {
      log(`socket error: ${error.message}`);
      this.emit("error", error);
    });
    socket.on("close", () => {
      this.connected = false;
      this.emit("close");
    });
  }

  onData(chunk) {
    this.receiveBuffer = Buffer.concat([this.receiveBuffer, chunk]);
    while (this.receiveBuffer.length >= REPORT_SIZE) {
      const frame = this.receiveBuffer.subarray(0, REPORT_SIZE);
      this.receiveBuffer = this.receiveBuffer.subarray(REPORT_SIZE);
      this.emit("data", Buffer.from(frame));
    }
  }

  write(data) {
    const frame = toFrame(data);
    if (this.connected && this.socket) this.socket.write(frame);
    else this.pendingFrames.push(frame);
    return Promise.resolve(frame.length);
  }

  read(timeout) {
    return new Promise((resolve) => {
      const onData = (data) => {
        if (timer) clearTimeout(timer);
        resolve(data);
      };
      const timer = timeout
        ? setTimeout(() => {
            this.off("data", onData);
            resolve(Buffer.alloc(0));
          }, timeout)
        : null;
      this.once("data", onData);
    });
  }

  getDeviceInfo() {
    return { ...FAKE_DESCRIPTOR };
  }

  sendFeatureReport() {
    return Promise.resolve(0);
  }
  getFeatureReport() {
    return Promise.resolve(Buffer.alloc(0));
  }
  setNonBlocking() {}
  pause() {}
  resume() {}

  close() {
    try {
      this.socket?.end();
    } catch {
      // Already closed.
    }
    return Promise.resolve();
  }
}

function isFakePath(devicePath) {
  return (
    devicePath === FAKE_PATH ||
    (typeof devicePath === "string" && devicePath.includes(FAKE_PATH))
  );
}

function patchModule(realModule, options = {}) {
  const socketPath = options.socketPath || defaultSocketPath();
  const patched = Object.create(realModule);

  patched.devices = function (...args) {
    let devices = [];
    try {
      devices = realModule.devices(...args) || [];
    } catch {
      // Preserve discovery even when the real backend is unavailable.
    }
    return devices.concat([{ ...FAKE_DESCRIPTOR }]);
  };

  if (typeof realModule.devicesAsync === "function") {
    patched.devicesAsync = async function (...args) {
      let devices = [];
      try {
        devices = (await realModule.devicesAsync(...args)) || [];
      } catch {
        // Preserve discovery even when the real backend is unavailable.
      }
      return devices.concat([{ ...FAKE_DESCRIPTOR }]);
    };
  }

  const RealAsync = realModule.HIDAsync;
  if (RealAsync) {
    patched.HIDAsync = new Proxy(RealAsync, {
      get(target, property, receiver) {
        if (property === "open") {
          return (devicePath, openOptions) =>
            isFakePath(devicePath)
              ? Promise.resolve(new FakeHIDAsync(socketPath))
              : RealAsync.open(devicePath, openOptions);
        }
        return Reflect.get(target, property, receiver);
      },
    });
  }

  log("node-hid patched");
  return patched;
}

function installHook(options = {}) {
  const Module = require("node:module");
  const originalLoad = Module._load;
  const patchedModules = new WeakMap();

  Module._load = function (request, parent, isMain) {
    const loaded = originalLoad.apply(this, arguments);
    if (looksLikeNodeHID(request, loaded)) {
      if (!patchedModules.has(loaded)) {
        patchedModules.set(loaded, patchModule(loaded, options));
      }
      return patchedModules.get(loaded);
    }
    return loaded;
  };
  log(`hook installed (socket=${options.socketPath || defaultSocketPath()})`);
}

function looksLikeNodeHID(request, module) {
  if (typeof request === "string" && /(^|[\\/])node-hid($|[\\/.])/.test(request)) {
    return true;
  }
  return Boolean(module && typeof module.devices === "function" && module.HIDAsync);
}

module.exports = {
  REPORT_SIZE,
  FAKE_PATH,
  FAKE_DESCRIPTOR,
  FakeHIDAsync,
  patchModule,
  installHook,
  defaultSocketPath,
};
