// The Fabricate ad's button and blast door sounds, mostly synthesised with Web Audio, plus a few
// recorded samples passed in as { name: url }. Times are in seconds from now; everything runs
// through one compressor and a short warehouse reverb, so the slam rings out like it's in a hangar.
// Each sample's volume is its own entry in the timeline's volumes.
import timeline from "./timeline";

const REVERB_S = 2.6;

export default class DoorSounds {
  constructor(samples = {}) {
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return;
    this.ctx = new Context();
    this.ctx.resume();
    this.noiseBuffer = buildNoise(this.ctx, 2);
    // Fetched and decoded now, so they're ready by the time the rocket lands. One that fails to
    // load just stays quiet.
    this.samples = Object.fromEntries(
      Object.entries(samples).map(([name, url]) => [
        name,
        fetch(url)
          .then((response) => response.arrayBuffer())
          .then((data) => this.ctx.decodeAudioData(data))
          .catch(() => null),
      ]),
    );

    const compressor = this.ctx.createDynamicsCompressor();
    compressor.connect(this.ctx.destination);
    this.out = this.ctx.createGain();
    this.out.connect(compressor);
    this.synth = this.ctx.createGain();
    this.synth.gain.value = timeline.volume.synth;
    this.synth.connect(this.out);
    const reverb = this.ctx.createConvolver();
    reverb.buffer = buildImpulse(this.ctx, REVERB_S);
    const wet = this.ctx.createGain();
    wet.gain.value = 0.35;
    this.out.connect(reverb).connect(wet).connect(compressor);
  }

  get now() {
    return this.ctx.currentTime;
  }

  // A tone that glides from `freq` to `to`, struck at `gain` and decaying over `dur`.
  tone({ at = 0, freq, to = freq, dur, gain, type = "sine" }) {
    if (!this.ctx) return;
    const start = this.now + at;
    const osc = this.ctx.createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, start);
    osc.frequency.exponentialRampToValueAtTime(to, start + dur);
    osc.connect(this.envelope(start, dur, gain));
    osc.start(start);
    osc.stop(start + dur);
  }

  // Filtered noise, struck at `gain` and decaying over `dur` (or swelling in, with `swell`).
  noise({
    at = 0,
    dur,
    gain,
    filter = "bandpass",
    freq = 1000,
    q = 1,
    swell = 0,
  }) {
    if (!this.ctx) return;
    const start = this.now + at;
    const source = this.ctx.createBufferSource();
    source.buffer = this.noiseBuffer;
    source.loop = true;
    const shape = this.ctx.createBiquadFilter();
    shape.type = filter;
    shape.frequency.value = freq;
    shape.Q.value = q;
    source.connect(shape).connect(this.envelope(start, dur, gain, swell));
    source.start(start, Math.random());
    source.stop(start + dur);
  }

  envelope(start, dur, gain, swell = 0) {
    const env = this.ctx.createGain();
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(gain, start + Math.max(0.004, swell));
    env.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    env.connect(this.synth);
    return env;
  }

  // The leaves grinding along their track, rollers ticking over the joints.
  rumble(dur) {
    this.noise({
      dur,
      gain: 0.5,
      filter: "lowpass",
      freq: 220,
      swell: dur * 0.8,
    });
    this.tone({ dur, freq: 38, to: 55, gain: 0.25, type: "sawtooth" });
    const ticks = Math.floor(dur / 0.06);
    for (let i = 0; i < ticks; i++)
      this.noise({
        at: i * 0.06 * (1 - i / ticks / 3),
        dur: 0.03,
        gain: 0.25,
        freq: 2600,
        q: 6,
      });
  }

  // Tonnes of steel meeting steel: a body-blow thump, an inharmonic ring and a crash of grit.
  clang() {
    this.tone({ freq: 90, to: 32, dur: 0.9, gain: 1 });
    this.noise({ dur: 0.5, gain: 0.9, freq: 2800, q: 0.7 });
    this.noise({ dur: 1.4, gain: 0.5, filter: "lowpass", freq: 400 });
    for (const [freq, dur] of [
      [187, 3.2],
      [403, 2.6],
      [619, 2.2],
      [866, 1.8],
      [1231, 1.4],
      [1704, 1.1],
      [2347, 0.8],
    ]) {
      const wobble = 1 + (Math.random() - 0.5) * 0.02;
      this.tone({ freq: freq * wobble, dur, gain: 0.12, type: "triangle" });
      this.tone({ freq: freq * wobble * 1.004, dur, gain: 0.08 });
    }
  }

  // A locking bolt throwing home.
  clunk(at = 0) {
    this.tone({ at, freq: 140, to: 60, dur: 0.18, gain: 0.7 });
    this.noise({ at, dur: 0.06, gain: 0.5, freq: 1800, q: 3 });
  }

  // One of the recorded samples, if it has loaded.
  async play(name) {
    const buffer = await this.samples?.[name];
    if (!buffer || this.ctx.state === "closed") return;
    const source = this.ctx.createBufferSource();
    source.buffer = buffer;
    const gain = this.ctx.createGain();
    gain.gain.value = timeline.volume[name];
    source.connect(gain).connect(this.out);
    source.start();
  }

  // The big red button going down.
  press() {
    this.tone({ freq: 220, to: 90, dur: 0.12, gain: 0.5, type: "square" });
    this.noise({ dur: 0.04, gain: 0.4, freq: 3000, q: 2 });
  }

  // Pausing the ad holds every sound mid-note, and playing picks them up again.
  suspend() {
    this.ctx?.suspend();
  }

  resume() {
    this.ctx?.resume();
  }

  close() {
    this.ctx?.close();
  }
}

function buildNoise(ctx, seconds) {
  const buffer = ctx.createBuffer(1, ctx.sampleRate * seconds, ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  return buffer;
}

function buildImpulse(ctx, seconds) {
  const length = ctx.sampleRate * seconds;
  const buffer = ctx.createBuffer(2, length, ctx.sampleRate);
  for (let channel = 0; channel < 2; channel++) {
    const data = buffer.getChannelData(channel);
    for (let i = 0; i < length; i++)
      data[i] = (Math.random() * 2 - 1) * (1 - i / length) ** 3;
  }
  return buffer;
}
