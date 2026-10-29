// A minute-long, letterboxed, fullscreen movie trailer for Fabricate that the visitor can't skip.
// It takes the whole screen, locks the keyboard (Escape included, where the browser allows it)
// and the pointer, swallows every key and click with a "DENIED" stamp, and ends by slamming the
// blast door and unlocking it for Fabricate to open. Browsers keep their own escape hatches
// (holding Escape, switching tabs, closing the window); when the visitor uses one the trailer
// simply keeps rolling.
import { animate, wait } from "./blast_door";

const RUNTIME_MS = 60_000;
const DOOR_AT_MS = 54_500;
const SKIP_FROM_MS = 40_000;
const STAMP_GAP_MS = 400;
const BLOCKED = [
  "keydown",
  "keyup",
  "keypress",
  "mousedown",
  "mouseup",
  "click",
  "dblclick",
  "contextmenu",
  "wheel",
  "touchstart",
  "touchmove",
];
const DENIALS = [
  "Denied",
  "Nope",
  "Input rejected",
  "Sit down",
  "Still no",
  "Welded shut",
  "Shhh",
  "Nice try",
];
const IDEAS = [
  "a keyboard with 400 keys",
  "a robot that feeds your cat",
  "an LED cube that plays Doom",
  "a toaster with Wi-Fi",
  "a drone made of popsicle sticks",
];

export default class Cutscene {
  constructor(door, sounds) {
    this.door = door;
    this.sounds = sounds;
    this.attempts = 0;
    this.timers = [];

    this.layer = document.createElement("div");
    this.layer.className = "fabricate-cutscene";
    this.layer.innerHTML = `
      <div class="fabricate-cutscene__stage"></div>
      <div class="fabricate-cutscene__hud">
        <span>Unskippable · <span data-clock>1:00</span></span>
        <span class="fabricate-cutscene__progress"><span class="fabricate-cutscene__progress-fill"></span></span>
        <span>Escape attempts: <span data-attempts>0</span></span>
      </div>`;
    this.stage = this.layer.querySelector(".fabricate-cutscene__stage");
    this.clock = this.layer.querySelector("[data-clock]");
    this.attemptCount = this.layer.querySelector("[data-attempts]");
    this.progress = this.layer.querySelector(
      ".fabricate-cutscene__progress-fill",
    );

    this.onInput = (event) => this.deny(event);
    this.onBeforeUnload = (event) => event.preventDefault();
    this.onFullscreenChange = () => {
      if (!document.fullscreenElement && this.locked)
        this.stamp("Fullscreen is a state of mind");
    };
  }

  // Must run inside the click, before anything awaits: fullscreen, keyboard lock and pointer lock
  // all need the click's user activation.
  lock() {
    this.locked = true;
    document.documentElement
      .requestFullscreen?.({ navigationUI: "hide" })
      .then(() => {
        navigator.keyboard?.lock?.();
        this.layer.requestPointerLock?.();
      })
      .catch(() => {});
    for (const type of BLOCKED)
      window.addEventListener(type, this.onInput, {
        capture: true,
        passive: false,
      });
    window.addEventListener("beforeunload", this.onBeforeUnload);
    document.addEventListener("fullscreenchange", this.onFullscreenChange);
  }

  release() {
    this.locked = false;
    for (const type of BLOCKED)
      window.removeEventListener(type, this.onInput, { capture: true });
    window.removeEventListener("beforeunload", this.onBeforeUnload);
    document.removeEventListener("fullscreenchange", this.onFullscreenChange);
    document.exitPointerLock?.();
    navigator.keyboard?.unlock?.();
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    speechSynthesis?.cancel();
  }

  deny(event) {
    event.preventDefault();
    event.stopImmediatePropagation();
    const attempt =
      event.type === "keydown"
        ? !event.repeat
        : ["mousedown", "touchstart", "wheel"].includes(event.type);
    if (!attempt) return;
    const now = performance.now();
    if (now - (this.lastStamp ?? 0) < STAMP_GAP_MS) return;
    this.lastStamp = now;
    this.attempts++;
    this.attemptCount.textContent = this.attempts;
    this.stamp(DENIALS[(this.attempts - 1) % DENIALS.length]);
    this.sounds.tone({ freq: 110, dur: 0.25, gain: 0.3, type: "square" });
    if (this.attempts % 4 === 0)
      this.say(
        "Please remain seated until the ad has come to a complete stop.",
      );
  }

  stamp(text) {
    this.layer.querySelector(".fabricate-cutscene__denied")?.remove();
    const stamp = document.createElement("div");
    stamp.className = "fabricate-cutscene__denied";
    stamp.textContent = text;
    this.layer.append(stamp);
  }

  say(text) {
    if (!window.speechSynthesis) return;
    const line = new SpeechSynthesisUtterance(text);
    line.pitch = 0.2;
    line.rate = 0.85;
    speechSynthesis.cancel();
    speechSynthesis.speak(line);
  }

  shot(html) {
    this.stage.innerHTML = `<div class="fabricate-cutscene__shot">${html}</div>`;
    return this.stage.firstElementChild;
  }

  at(ms, scene) {
    this.timers.push(setTimeout(scene, ms));
  }

  async play() {
    this.door.overlay.prepend(this.layer);
    this.start = performance.now();
    this.tickHud();
    this.drone();

    this.at(0, () =>
      this.shot(
        `<p class="fabricate-cutscene__small">Hack Club Pictures presents</p>`,
      ),
    );
    this.at(4000, () => {
      this.shot(`<p class="fabricate-cutscene__line">In a world…</p>`);
      this.say("In a world");
    });
    this.at(6500, () => {
      this.shot(
        `<p class="fabricate-cutscene__line">…where hardware is expensive…</p>`,
      );
      this.say("where hardware is expensive");
    });
    this.at(10_500, () => this.ideas());
    this.at(16_000, () => this.broke());
    this.at(21_000, () => {
      this.shot(`<p class="fabricate-cutscene__line">One program…</p>`);
      this.say("One program dared to pay for it.");
    });
    this.at(23_500, () =>
      this.shot(
        `<p class="fabricate-cutscene__line">…dared to pay for it.</p>`,
      ),
    );
    this.at(26_500, () => this.title());
    this.at(30_500, () => this.cut("Design it."));
    this.at(32_300, () => this.funded());
    this.at(35_100, () => this.cut("Build it."));
    this.at(36_900, () => this.cut("Get prizes."));
    this.at(38_700, () => this.cut("Repeat."));
    this.at(40_500, () => this.rating());
    this.at(SKIP_FROM_MS, () => this.fakeSkip());
    this.at(45_500, () => this.install());
    this.at(50_000, () => {
      this.shot(
        `<p class="fabricate-cutscene__line">This ad cannot be skipped.</p><p class="fabricate-cutscene__small">(we checked)</p>`,
      );
      this.say("This ad cannot be skipped.");
    });
    this.at(52_500, () => {
      this.shot(
        `<p class="fabricate-cutscene__line">Prepare for fabrication.</p>`,
      );
      this.say("Prepare for fabrication.");
    });

    await wait(DOOR_AT_MS);
    this.skip?.remove();
    await this.door.slam();
    this.layer.remove();
    await this.door.unlock();
    await wait(Math.max(0, RUNTIME_MS - (performance.now() - this.start)));
    this.release();
  }

  tickHud() {
    const elapsed = performance.now() - this.start;
    const left = Math.max(0, Math.ceil((RUNTIME_MS - elapsed) / 1000));
    this.clock.textContent = `0:${String(left).padStart(2, "0")}`;
    this.progress.style.width = `${Math.min(100, (elapsed / RUNTIME_MS) * 100)}%`;
    if (elapsed < RUNTIME_MS && this.layer.isConnected)
      this.timers.push(setTimeout(() => this.tickHud(), 250));
  }

  // A low, ominous trailer drone under the whole thing.
  drone() {
    this.sounds.tone({
      freq: 55,
      to: 52,
      dur: DOOR_AT_MS / 1000,
      gain: 0.08,
      type: "sawtooth",
    });
    this.sounds.tone({
      freq: 82.5,
      to: 80,
      dur: DOOR_AT_MS / 1000,
      gain: 0.05,
      type: "sawtooth",
    });
  }

  ideas() {
    const cards = IDEAS.map(
      (idea) => `<span class="fabricate-cutscene__idea">${idea}</span>`,
    ).join("");
    this.shot(
      `<p class="fabricate-cutscene__line">Teenagers have ideas.</p><div class="fabricate-cutscene__ideas">${cards}</div>`,
    );
    this.say("Teenagers have ideas.");
  }

  broke() {
    this.shot(
      `<p class="fabricate-cutscene__money">$0.00</p><p class="fabricate-cutscene__line">…but no money.</p>`,
    );
    this.say("But no money.");
    // Sad trombone.
    [
      [311, 293],
      [293, 277],
      [277, 262],
      [262, 220],
    ].forEach(([from, to], i) =>
      this.sounds.tone({
        at: 1 + i * 0.55,
        freq: from,
        to,
        dur: i === 3 ? 1.4 : 0.5,
        gain: 0.25,
        type: "sawtooth",
      }),
    );
  }

  title() {
    this.shot(
      `<p class="fabricate-cutscene__small">By Hack Club, for teens 13–18</p><h1 class="fabricate-cutscene__title">FABRICATE</h1>`,
    );
    this.say("Fabricate.");
    setTimeout(() => {
      this.sounds.clang();
      this.door.shake(800, 26);
    }, 420);
  }

  cut(text) {
    this.shot(`<p class="fabricate-cutscene__title">${text}</p>`);
    this.sounds.clunk();
    this.door.shake(250, 8);
  }

  funded() {
    const shot = this.shot(
      `<p class="fabricate-cutscene__line">Get funded up to</p><p class="fabricate-cutscene__money">$0</p>`,
    );
    const money = shot.querySelector(".fabricate-cutscene__money");
    this.say("Get funded up to five hundred dollars.");
    animate(1600, (u) => {
      money.textContent = `$${Math.round(500 * (1 - (1 - u) ** 3))}`;
    }).then(() => this.sounds.clunk());
  }

  rating() {
    this.shot(`
      <div class="fabricate-cutscene__rating">
        <span class="fabricate-cutscene__rating-letter">T</span>
        <p class="fabricate-cutscene__small">Rated T for Teens 13–18. Contains soldering, mild PCB violence, and extreme funding. Ends December 31.</p>
      </div>`);
    this.say("Rated T, for teens.");
  }

  install() {
    const shot = this.shot(`
      <p class="fabricate-cutscene__line">Installing Fabricate into your brain…</p>
      <div class="fabricate-cutscene__bar"><div class="fabricate-cutscene__bar-fill"></div></div>
      <p class="fabricate-cutscene__small" data-percent>0%</p>`);
    const fill = shot.querySelector(".fabricate-cutscene__bar-fill");
    const percent = shot.querySelector("[data-percent]");
    // Races to 99% and stays there, as is tradition.
    animate(2200, (u) => {
      const value = Math.floor(99 * (1 - (1 - u) ** 2));
      fill.style.width = `${value}%`;
      percent.textContent = `${value}%`;
    });
  }

  // A skip button that counts down, offers itself for a second, then thinks better of it.
  fakeSkip() {
    this.skip = document.createElement("div");
    this.skip.className = "fabricate-cutscene__skip";
    this.layer.append(this.skip);
    const script = [
      ...[5, 4, 3, 2, 1].map((n) => `Skip ad in ${n}`),
      "Skip ad ▶",
      "lol no",
      ...[9, 8, 7, 6, 5, 4].map((n) => `Skip ad in ${n}`),
      "Skip ad in ∞",
    ];
    script.forEach((text, i) =>
      this.at(i * 1000, () => {
        if (this.skip) this.skip.textContent = text;
      }),
    );
  }

  destroy() {
    this.timers.forEach(clearTimeout);
    this.release();
    this.layer.remove();
  }
}
