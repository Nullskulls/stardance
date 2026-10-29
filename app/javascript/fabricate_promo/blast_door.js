// The Fabricate ad's toothed blast door at full screen. It stamps out the widget's door template,
// starts with both leaves slid out of sight, slams them shut over the page, shakes the screen and
// throws the bolts. It ends shut: Fabricate draws the same door over its landing page and opens
// it there, so the visitor arrives behind it.
//
// The door is drawn from a time, in seconds since it started closing (see `at`), so it can be
// played, paused and scrubbed as part of a sequence. Its sounds are `events` on that same clock.
import Sequence from "./sequence";
import timeline from "./timeline";

const BOLT_JOLT_PX = 5;

export default class BlastDoor {
  constructor(template, sounds) {
    this.sounds = sounds;
    this.overlay = document.createElement("div");
    this.overlay.className = "fabricate-promo__overlay";
    this.overlay.setAttribute("aria-hidden", "true");

    this.door = template.content.firstElementChild.cloneNode(true);
    this.setGap(1);
    this.overlay.append(this.door);
  }

  mount() {
    document.body.append(this.overlay);
  }

  // The door's beats, in seconds since it started closing.
  get beats() {
    const { closeMs, settleMs, bolts, boltMs } = timeline.door;
    const shut = closeMs / 1000;
    const unlocking = shut + settleMs / 1000;
    return { shut, unlocking, unlocked: unlocking + (bolts * boltMs) / 1000 };
  }

  get length() {
    return this.beats.unlocked;
  }

  // The door as it stands `time` seconds after it started closing.
  at(time) {
    const { shut, unlocking } = this.beats;
    const { shakeMs, shakePx, bolts, boltMs } = timeline.door;
    this.setGap(1 - easeIn(clamp(time / shut)));
    // Fabricate is behind the door once the leaves have met.
    this.door.classList.toggle("fabricate-door--hollow", time < shut);

    let jolt = joltAt(time - shut, shakeMs / 1000, shakePx);
    for (let bolt = 0; bolt < bolts; bolt++) {
      const thrown = unlocking + (bolt * boltMs) / 1000;
      jolt = addJolts(
        jolt,
        joltAt(time - thrown, (boltMs * 0.7) / 1000, BOLT_JOLT_PX),
      );
    }
    applyJolt(this.overlay, jolt);
  }

  // The door's sounds, in seconds since it started closing. Lengths are scaled to the current
  // speed as each one plays.
  get events() {
    const { shut, unlocking } = this.beats;
    const { bolts, boltMs, pipeDelayMs } = timeline.door;
    const scaled = (s) => s / timeline.speed;
    return [
      { at: 0, run: () => this.sounds.rumble(scaled(shut)) },
      {
        at: shut,
        run: () => {
          this.sounds.clang();
          navigator.vibrate?.([120, 40, 60]);
        },
      },
      { at: shut + pipeDelayMs / 1000, run: () => this.sounds.play("pipe") },
      ...Array.from({ length: bolts }, (_, bolt) => ({
        at: unlocking + (bolt * boltMs) / 1000,
        run: () => this.sounds.clunk(),
      })),
    ];
  }

  setGap(gap) {
    this.door.style.setProperty("--fabricate-door-gap", gap);
  }

  // Real-time playback of the door on its own, a beat at a time, for the cutscene.
  slam() {
    return this.playBetween(0, this.beats.unlocking);
  }

  unlock() {
    return this.playBetween(this.beats.unlocking, this.beats.unlocked);
  }

  playBetween(from, to) {
    return new Sequence({
      from,
      to,
      render: (time) => this.at(time),
      events: this.events,
    }).play();
  }

  shake(ms, px) {
    shake(this.overlay, ms, px);
  }

  destroy() {
    this.overlay.remove();
  }
}

// How far a jolt `elapsed` seconds into it has thrown things, dying away over `duration`. The
// wobble is hashed from the time, so the same moment always shakes the same way.
export function joltAt(elapsed, duration, px) {
  if (elapsed < 0 || elapsed >= duration) return { x: 0, y: 0 };
  const amount = px * (1 - elapsed / duration) ** 2;
  const frame = Math.floor(elapsed * 60);
  return { x: noise(frame) * amount, y: noise(frame + 7919) * amount };
}

export function applyJolt(element, { x, y }) {
  element.style.transform =
    x || y ? `translate(${x}px, ${y}px) rotate(${x * 0.02}deg)` : "";
}

// Jolts `element` about in real time, dying away over `ms`. Only ever pass something inside the
// fixed overlay: moving the page itself pushes it past the viewport and flashes the scrollbars.
export function shake(element, ms, px) {
  return animate(ms, (u) =>
    applyJolt(element, joltAt((u * ms) / 1000, ms / 1000, px)),
  );
}

export function animate(ms, step) {
  return new Promise((resolve) => {
    let start;
    const frame = (now) => {
      start ??= now;
      const u = Math.min(1, (now - start) / ms);
      step(u);
      if (u < 1) requestAnimationFrame(frame);
      else resolve();
    };
    requestAnimationFrame(frame);
  });
}

export const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const clamp = (u) => Math.min(1, Math.max(0, u));
const addJolts = (a, b) => ({ x: a.x + b.x, y: a.y + b.y });
const noise = (n) => {
  const s = Math.sin(n * 12.9898) * 43758.5453;
  return (s - Math.floor(s)) * 2 - 1;
};
const easeIn = (t) => t * t * t;
