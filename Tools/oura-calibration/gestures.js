// Gesture-labeling prompt engine for the Oura tap/flick classifier dataset.
//
// Serve with serve.py (same capture pipeline as index.html/app.js); labeled
// trial windows land in the capture dir's targets.ndjson. The app-side
// full-rate motion trace (defaults write KevinTang.XboxControllerMapper
// ouraMotionTraceLogging -bool true) must be enabled so analyze_gestures.py
// can join prompts to accelerometer samples by wall-clock time.

const CLASSES = [
	{ id: "single-tap", label: "SINGLE TAP", hint: "One crisp tap", reps: 12, windowSeconds: 2.0, expect: { taps: 1 } },
	{ id: "double-tap", label: "DOUBLE TAP", hint: "Two quick taps", reps: 12, windowSeconds: 2.5, expect: { taps: 2 } },
	{ id: "triple-tap", label: "TRIPLE TAP", hint: "Three quick taps", reps: 12, windowSeconds: 3.0, expect: { taps: 3 } },
	{ id: "five-tap", label: "5x TAP", hint: "Five quick taps", reps: 10, windowSeconds: 4.0, expect: { taps: 5 } },
	{ id: "flick-up", label: "FLICK UP", hint: "One sharp flick upward", reps: 10, windowSeconds: 2.0, expect: { flick: "up" } },
	{ id: "flick-down", label: "FLICK DOWN", hint: "One sharp flick downward", reps: 10, windowSeconds: 2.0, expect: { flick: "down" } },
	{ id: "flick-left", label: "FLICK LEFT", hint: "One sharp flick to the left", reps: 10, windowSeconds: 2.0, expect: { flick: "left" } },
	{ id: "flick-right", label: "FLICK RIGHT", hint: "One sharp flick to the right", reps: 10, windowSeconds: 2.0, expect: { flick: "right" } },
	{ id: "tap-hold", label: "TAP + HOLD", hint: "Tap once, then press and hold", reps: 8, windowSeconds: 2.5, expect: { tapHold: true } },
	{ id: "noise-still", label: "HOLD STILL", hint: "Do nothing — hand relaxed", reps: 4, windowSeconds: 5.0, expect: { none: true } },
	{ id: "noise-move", label: "MOVE CURSOR", hint: "Move the cursor around normally — no taps, no flicks", reps: 6, windowSeconds: 5.0, expect: { none: true } }
];

const PREPARE_SECONDS = 1.4;
const REST_SECONDS = 1.2;
const REST_JITTER_SECONDS = 0.4;

const sessionId = new Date().toISOString().replace(/[:.]/g, "-");
const stage = document.getElementById("stage");
const status = document.getElementById("status");
const setupScreen = document.getElementById("setup");
const runScreen = document.getElementById("run");
const doneScreen = document.getElementById("done");
const phaseBanner = document.getElementById("phaseBanner");
const promptText = document.getElementById("prompt");
const hintText = document.getElementById("hint");
const progressBar = document.getElementById("progressBar");
const doneSummary = document.getElementById("doneSummary");
const scaleSelect = document.getElementById("scale");
const startButton = document.getElementById("startButton");
const fullScreenButton = document.getElementById("fullScreenButton");

let running = false;
let trials = [];
let trialIndex = 0;
let completedCount = 0;
let discardedCount = 0;
let currentTrial = null;
let currentPhase = "idle";
let phaseTimer = null;
let progressTimer = null;
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
	try {
		await fetch("/api/event", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(payload)
		});
	} catch {
		status.textContent = "Offline — events not captured!";
	}
	return payload;
}

function beep(frequency, durationMs) {
	try {
		if (!audioContext) {
			audioContext = new (window.AudioContext || window.webkitAudioContext)();
		}
		const osc = audioContext.createOscillator();
		const gain = audioContext.createGain();
		osc.frequency.value = frequency;
		osc.type = "sine";
		gain.gain.setValueAtTime(0.22, audioContext.currentTime);
		gain.gain.exponentialRampToValueAtTime(0.001, audioContext.currentTime + durationMs / 1000);
		osc.connect(gain);
		gain.connect(audioContext.destination);
		osc.start();
		osc.stop(audioContext.currentTime + durationMs / 1000);
	} catch {
		// Audio is a nicety; the visual phase cues carry the session.
	}
}

function shuffle(list) {
	const out = list.slice();
	for (let i = out.length - 1; i > 0; i--) {
		const j = Math.floor(Math.random() * (i + 1));
		[out[i], out[j]] = [out[j], out[i]];
	}
	return out;
}

function buildTrialList(scale) {
	const list = [];
	for (const cls of CLASSES) {
		const reps = Math.max(1, Math.round(cls.reps * scale));
		for (let i = 0; i < reps; i++) {
			list.push(cls);
		}
	}
	return shuffle(list);
}

function setPhase(phaseName) {
	currentPhase = phaseName;
	stage.classList.remove("phase-prepare", "phase-go", "phase-rest");
	if (phaseName !== "idle") {
		stage.classList.add(`phase-${phaseName}`);
	}
}

function clearTimers() {
	if (phaseTimer) { clearTimeout(phaseTimer); phaseTimer = null; }
	if (progressTimer) { clearInterval(progressTimer); progressTimer = null; }
	progressBar.style.width = "0%";
}

function updateStatus() {
	status.textContent = `Trial ${Math.min(trialIndex + 1, trials.length)} / ${trials.length}`;
}

function trialPayload(cls) {
	return {
		label: cls.id,
		classId: cls.id,
		trialIndex,
		windowSeconds: cls.windowSeconds,
		expect: cls.expect
	};
}

function startNextTrial() {
	if (!running) { return; }
	if (trialIndex >= trials.length) {
		finishSession("completed");
		return;
	}
	const cls = trials[trialIndex];
	currentTrial = cls;
	updateStatus();

	setPhase("prepare");
	phaseBanner.textContent = "Next";
	promptText.textContent = cls.label;
	hintText.textContent = cls.hint;
	postEvent({ type: "trial:prepare", ...trialPayload(cls) });

	phaseTimer = setTimeout(() => beginGo(cls), PREPARE_SECONDS * 1000);
}

function beginGo(cls) {
	if (!running) { return; }
	setPhase("go");
	phaseBanner.textContent = "GO";
	beep(880, 90);
	postEvent({ type: "trial:go", ...trialPayload(cls) });

	const goStartMs = performance.now();
	const windowMs = cls.windowSeconds * 1000;
	progressTimer = setInterval(() => {
		const fraction = Math.min(1, (performance.now() - goStartMs) / windowMs);
		progressBar.style.width = `${(fraction * 100).toFixed(1)}%`;
	}, 50);

	phaseTimer = setTimeout(() => endTrial(cls), windowMs);
}

function endTrial(cls) {
	if (!running) { return; }
	clearTimers();
	beep(440, 80);
	postEvent({ type: "trial:end", ...trialPayload(cls) });

	setPhase("rest");
	phaseBanner.textContent = "Rest";
	hintText.textContent = "Relax your hand";
	trialIndex += 1;
	completedCount += 1;
	currentTrial = null;
	updateStatus();

	// Rest padding ≥1.2s deliberately clears the app's 0.75s post-recenter
	// tap-suppression window so trials never bleed into each other.
	const restMs = (REST_SECONDS + Math.random() * REST_JITTER_SECONDS) * 1000;
	phaseTimer = setTimeout(startNextTrial, restMs);
}

function discardLast() {
	if (!running) { return; }
	if (currentTrial) {
		// Mid-trial: abort this one, re-queue the same class at the end.
		clearTimers();
		postEvent({ type: "trial:discard", ...trialPayload(currentTrial), scope: "current" });
		trials.push(currentTrial);
		trials.splice(trialIndex, 1);
		discardedCount += 1;
		currentTrial = null;
		setPhase("rest");
		phaseBanner.textContent = "Discarded";
		hintText.textContent = "Trial re-queued";
		phaseTimer = setTimeout(startNextTrial, REST_SECONDS * 1000);
	} else if (completedCount > 0) {
		// Between trials: retract the one that just ended, re-queue it.
		const lastCls = trials[trialIndex - 1];
		postEvent({
			type: "trial:discard",
			label: lastCls.id,
			classId: lastCls.id,
			trialIndex: trialIndex - 1,
			scope: "previous"
		});
		trials.push(lastCls);
		completedCount -= 1;
		discardedCount += 1;
		phaseBanner.textContent = "Discarded";
		hintText.textContent = "Previous trial re-queued";
		updateStatus();
	}
}

function finishSession(reason) {
	running = false;
	clearTimers();
	setPhase("idle");
	postEvent({ type: "session:end", reason, completedCount, discardedCount });
	runScreen.style.display = "none";
	doneScreen.style.display = "block";
	status.textContent = "Done";
	doneSummary.textContent =
		`${completedCount} labeled trial${completedCount === 1 ? "" : "s"} captured` +
		(discardedCount > 0 ? `, ${discardedCount} discarded` : "") +
		(reason === "aborted" ? " (session ended early)" : "") + ".";
}

function startSession() {
	const scale = parseFloat(scaleSelect.value) || 1;
	trials = buildTrialList(scale);
	trialIndex = 0;
	completedCount = 0;
	discardedCount = 0;
	running = true;

	postEvent({
		type: "session:start",
		kind: "gesture-labeling",
		scale,
		prepareSeconds: PREPARE_SECONDS,
		restSeconds: REST_SECONDS,
		restJitterSeconds: REST_JITTER_SECONDS,
		classes: CLASSES.map((cls) => ({
			id: cls.id,
			reps: Math.max(1, Math.round(cls.reps * scale)),
			windowSeconds: cls.windowSeconds,
			expect: cls.expect
		})),
		totalTrials: trials.length
	});

	setupScreen.style.display = "none";
	runScreen.style.display = "block";
	startNextTrial();
}

startButton.addEventListener("click", startSession);
fullScreenButton.addEventListener("click", () => {
	if (document.fullscreenElement) {
		document.exitFullscreen();
	} else {
		document.documentElement.requestFullscreen();
	}
});

window.addEventListener("keydown", (event) => {
	if (event.key === "Backspace") {
		event.preventDefault();
		discardLast();
	} else if (event.key === "Escape" && running) {
		finishSession("aborted");
	}
});
