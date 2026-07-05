const TARGETS = [
	{ id: "center", label: "Center", x: 0, y: 0 },
	{ id: "left", label: "Left", x: -0.72, y: 0 },
	{ id: "center-a", label: "Center", x: 0, y: 0 },
	{ id: "right", label: "Right", x: 0.72, y: 0 },
	{ id: "center-b", label: "Center", x: 0, y: 0 },
	{ id: "up", label: "Up", x: 0, y: -0.64 },
	{ id: "center-c", label: "Center", x: 0, y: 0 },
	{ id: "down", label: "Down", x: 0, y: 0.64 },
	{ id: "center-d", label: "Center", x: 0, y: 0 },
	{ id: "upper-left", label: "Upper left", x: -0.58, y: -0.52 },
	{ id: "upper-right", label: "Upper right", x: 0.58, y: -0.52 },
	{ id: "lower-right", label: "Lower right", x: 0.58, y: 0.52 },
	{ id: "lower-left", label: "Lower left", x: -0.58, y: 0.52 },
	{ id: "center-final", label: "Center", x: 0, y: 0 }
];

const CONFIG = {
	prepareSeconds: 1.2,
	holdSeconds: 3.4,
	countdownSeconds: 3
};

const sessionId = new Date().toISOString().replace(/[:.]/g, "-");
const stage = document.getElementById("stage");
const target = document.getElementById("target");
const direction = document.getElementById("direction");
const phase = document.getElementById("phase");
const status = document.getElementById("status");
const meterFill = document.getElementById("meterFill");
const countdown = document.getElementById("countdown");
const countdownNumber = document.getElementById("countdownNumber");
const countdownText = document.getElementById("countdownText");
const startButton = document.getElementById("startButton");
const fullScreenButton = document.getElementById("fullScreenButton");
const exportButton = document.getElementById("exportButton");

let events = [];
let running = false;
let completed = false;
let audioContext = null;

function eventBase() {
	return {
		sessionId,
		wallTimeIso: new Date().toISOString(),
		wallTimeUnix: Date.now() / 1000,
		performanceMs: performance.now(),
		viewport: {
			width: window.innerWidth,
			height: window.innerHeight,
			devicePixelRatio: window.devicePixelRatio || 1
		}
	};
}

async function postEvent(event) {
	const payload = { ...eventBase(), ...event };
	events.push(payload);
	try {
		await fetch("/api/event", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(payload)
		});
	} catch {
		status.textContent = "Offline capture";
	}
	return payload;
}

function setTarget(nextTarget, mode) {
	const left = 50 + nextTarget.x * 42;
	const top = 50 + nextTarget.y * 42;
	target.style.left = `${left}%`;
	target.style.top = `${top}%`;
	target.classList.toggle("hold", mode === "hold");
	target.classList.toggle("rest", mode !== "hold");
	direction.textContent = nextTarget.label;
	phase.textContent = mode === "hold" ? "Hold steady" : "Move to target";
}

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

function beep(frequency, durationMs) {
	if (!audioContext) {
		audioContext = new (window.AudioContext || window.webkitAudioContext)();
	}
	const now = audioContext.currentTime;
	const oscillator = audioContext.createOscillator();
	const gain = audioContext.createGain();
	oscillator.frequency.value = frequency;
	oscillator.type = "sine";
	gain.gain.setValueAtTime(0.0001, now);
	gain.gain.exponentialRampToValueAtTime(0.12, now + 0.015);
	gain.gain.exponentialRampToValueAtTime(0.0001, now + durationMs / 1000);
	oscillator.connect(gain);
	gain.connect(audioContext.destination);
	oscillator.start(now);
	oscillator.stop(now + durationMs / 1000);
}

async function countdownRun() {
	countdown.classList.remove("hidden");
	countdownText.textContent = "Point at center";
	for (let remaining = CONFIG.countdownSeconds; remaining > 0; remaining -= 1) {
		countdownNumber.textContent = String(remaining);
		beep(420 + remaining * 60, 90);
		await sleep(1000);
	}
	countdown.classList.add("hidden");
}

function updateMeter(done, total) {
	meterFill.style.width = `${Math.max(0, Math.min(100, (done / total) * 100))}%`;
}

async function timedPhase(seconds, onTick) {
	const started = performance.now();
	const duration = seconds * 1000;
	while (performance.now() - started < duration) {
		onTick((performance.now() - started) / duration);
		await sleep(80);
	}
	onTick(1);
}

async function runCalibration() {
	if (running) return;
	running = true;
	completed = false;
	events = [];
	exportButton.disabled = true;
	startButton.disabled = true;
	setTarget(TARGETS[0], "rest");

	await postEvent({ type: "session:start", config: CONFIG, targets: TARGETS });
	await countdownRun();

	const totalPhases = TARGETS.length * 2;
	let phaseIndex = 0;
	for (let trialIndex = 0; trialIndex < TARGETS.length; trialIndex += 1) {
		const nextTarget = TARGETS[trialIndex];
		setTarget(nextTarget, "rest");
		status.textContent = `${trialIndex + 1}/${TARGETS.length} prepare`;
		await postEvent({ type: "target:prepare", trialIndex, target: nextTarget });
		await timedPhase(CONFIG.prepareSeconds, progress => updateMeter(phaseIndex + progress, totalPhases));
		phaseIndex += 1;

		setTarget(nextTarget, "hold");
		status.textContent = `${trialIndex + 1}/${TARGETS.length} hold`;
		beep(820, 120);
		await postEvent({ type: "target:start", trialIndex, target: nextTarget });
		await timedPhase(CONFIG.holdSeconds, progress => updateMeter(phaseIndex + progress, totalPhases));
		await postEvent({ type: "target:end", trialIndex, target: nextTarget });
		phaseIndex += 1;
	}

	updateMeter(totalPhases, totalPhases);
	status.textContent = "Complete";
	phase.textContent = "Capture complete";
	completed = true;
	running = false;
	startButton.disabled = false;
	startButton.textContent = "Run again";
	exportButton.disabled = false;
	await postEvent({ type: "session:end" });
	beep(560, 120);
	setTimeout(() => beep(760, 120), 150);
}

function exportEvents() {
	const body = JSON.stringify({ sessionId, config: CONFIG, targets: TARGETS, events }, null, 2);
	const blob = new Blob([body], { type: "application/json" });
	const url = URL.createObjectURL(blob);
	const anchor = document.createElement("a");
	anchor.href = url;
	anchor.download = `oura-calibration-${sessionId}.json`;
	document.body.appendChild(anchor);
	anchor.click();
	anchor.remove();
	URL.revokeObjectURL(url);
}

startButton.addEventListener("click", runCalibration);
exportButton.addEventListener("click", exportEvents);
fullScreenButton.addEventListener("click", () => {
	if (!document.fullscreenElement) {
		stage.requestFullscreen?.();
	} else {
		document.exitFullscreen?.();
	}
});

window.addEventListener("keydown", event => {
	if (event.code === "Space") {
		event.preventDefault();
		if (!running) runCalibration();
	}
	if (event.key.toLowerCase() === "f") {
		event.preventDefault();
		fullScreenButton.click();
	}
	if (event.key.toLowerCase() === "e" && completed) {
		event.preventDefault();
		exportEvents();
	}
});

setTarget(TARGETS[0], "rest");
postEvent({ type: "page:ready", config: CONFIG, targets: TARGETS });
