window.addEventListener('DOMContentLoaded', function() {
    const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : "pickle_moneywash";
    fetch(`https://${resourceName}/pageLoaded`).then(function(response) {
        // PRODUCTION MODE
    }).catch(function(error) {
        // DEBUG MODE
    });
    // setTimeout(function() {
    //     window.postMessage({
    //         type: "setConfig",
    //         config: {
    //             identifier: "char:1",
    //         }
    //     }, '*');
    // }, 1000);
});

// =========================
// Generic NUI sound player (WebAudio) with volume + stereo panning
// Controlled from Lua via SendNUIMessage (window postMessage).
//
// Messages:
// - { type: "pmw_sound_play", id, path, volume, pan, loop, rate }
// - { type: "pmw_sound_update", id, volume, pan, rate }
// - { type: "pmw_sound_stop", id }
// =========================
(function () {
    const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
    const ctx = AudioContextCtor ? new AudioContextCtor() : null;
    const sounds = new Map(); // id -> { audio, source, gain, panner }

    const clamp = (v, min, max) => Math.max(min, Math.min(max, v));

    const isSafePath = (p) => {
        if (typeof p !== "string") return false;
        if (!p.length) return false;
        if (p.includes("..")) return false;
        if (p.includes(":")) return false;
        if (p.includes("\\")) return false;
        if (p.startsWith("/")) return false;
        return true;
    };

    const toUrl = (path) => `/nui/${path}`;

    const resume = async () => {
        if (!ctx) return;
        if (ctx.state === "suspended") {
            try { await ctx.resume(); } catch (e) {}
        }
    };

    const cleanup = (id) => {
        const s = sounds.get(id);
        if (!s) return;
        try {
            if (s.audio) {
                s.audio.pause();
                s.audio.src = "";
            }
        } catch (e) {}
        try { s.source && s.source.disconnect(); } catch (e) {}
        try { s.panner && s.panner.disconnect(); } catch (e) {}
        try { s.gain && s.gain.disconnect(); } catch (e) {}
        sounds.delete(id);
    };

    const ensureNodes = (audio) => {
        if (!ctx) return null;
        const source = ctx.createMediaElementSource(audio);
        const gain = ctx.createGain();
        const panner = ctx.createStereoPanner ? ctx.createStereoPanner() : null;

        if (panner) {
            source.connect(panner);
            panner.connect(gain);
        } else {
            source.connect(gain);
        }
        gain.connect(ctx.destination);
        return { source, gain, panner };
    };

    const play = async (msg) => {
        const { id, path } = msg || {};
        if (!id || !isSafePath(path)) return;
        if (!ctx) return;

        cleanup(id);
        await resume();

        const audio = new Audio(toUrl(path));
        audio.preload = "auto";
        audio.loop = !!msg.loop;
        audio.crossOrigin = "anonymous";

        if (typeof msg.rate === "number") {
            audio.playbackRate = clamp(msg.rate, 0.25, 4.0);
        }

        const nodes = ensureNodes(audio);
        if (!nodes) return;

        nodes.gain.gain.value = clamp(typeof msg.volume === "number" ? msg.volume : 1.0, 0.0, 1.0);
        if (nodes.panner) {
            nodes.panner.pan.value = clamp(typeof msg.pan === "number" ? msg.pan : 0.0, -1.0, 1.0);
        }

        audio.addEventListener("ended", () => cleanup(id));
        audio.addEventListener("error", () => cleanup(id));
        sounds.set(id, { audio, ...nodes });

        try {
            await audio.play();
        } catch (e) {
            cleanup(id);
        }
    };

    const update = async (msg) => {
        const { id } = msg || {};
        if (!id) return;
        const s = sounds.get(id);
        if (!s) return;
        await resume();

        if (typeof msg.volume === "number") {
            s.gain.gain.value = clamp(msg.volume, 0.0, 1.0);
        }
        if (s.panner && typeof msg.pan === "number") {
            s.panner.pan.value = clamp(msg.pan, -1.0, 1.0);
        }
        if (s.audio && typeof msg.rate === "number") {
            s.audio.playbackRate = clamp(msg.rate, 0.25, 4.0);
        }
    };

    const stop = (msg) => {
        const { id } = msg || {};
        if (!id) return;
        cleanup(id);
    };

    window.addEventListener("message", (event) => {
        const msg = event.data;
        if (!msg || typeof msg !== "object") return;

        if (msg.type === "pmw_sound_play") play(msg);
        else if (msg.type === "pmw_sound_update") update(msg);
        else if (msg.type === "pmw_sound_stop") stop(msg);
    });
})();