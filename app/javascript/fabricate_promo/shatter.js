// The page the rocket hits, smashed. Each shard is a frozen copy of the site clipped to a wedge
// fanning out from the shatter's origin (timeline.shatter.x and y, set apart from where the
// explosion lands), so when the copies crack apart and fall it looks like the page
// itself breaking. The copies are cut ahead of the click, a piece at a time in idle moments, and
// stay hidden over the real page from the click until the rocket lands.
//
// Like the door, it's drawn from a time (`at`), in seconds into the strike, so it can be scrubbed.
import { applyJolt, joltAt } from "./blast_door";
import { cancelIdle, whenIdle } from "./idle";
import timeline from "./timeline";

const SVG = "http://www.w3.org/2000/svg";

export default class Shatter {
  constructor() {
    this.width = window.innerWidth;
    this.height = window.innerHeight;
    this.origin = {
      x: this.width * timeline.shatter.x,
      y: this.height * timeline.shatter.y,
    };
    this.layer = document.createElement("div");
    this.layer.className = "fabricate-shatter";
    this.pieces = document.createElement("div");
    this.pieces.className = "fabricate-shatter__pieces";
    this.layer.append(this.pieces);
    this.shards = [];
    this.steps = this.build();
  }

  // The page is copied once, then cut into shards one at a time. Each step is a few milliseconds,
  // and nothing joins the document until `mount`, so building it costs the page no layout.
  *build() {
    this.template = this.snapshot();
    yield;
    const rays = castRays();
    const cracks = this.drawCracks(rays);
    for (const [i, from] of rays.entries()) {
      yield;
      this.shards.push(
        this.cutShard(from, rays[i + 1] ?? rays[0] + Math.PI * 2, cracks),
      );
    }
  }

  // Works through the build while the browser has nothing else to do.
  prebuild() {
    const step = () => {
      this.idle = this.steps.next().done ? null : whenIdle(step);
    };
    this.idle ??= whenIdle(step);
  }

  // Cut for a window of another size, the shards would no longer meet at the origin.
  get stale() {
    return (
      this.width !== window.innerWidth || this.height !== window.innerHeight
    );
  }

  // Under everything else in the overlay, so the fire and the door play over the wreckage. Whatever
  // the idle time didn't get to is built now.
  mount(overlay) {
    if (this.idle) cancelIdle(this.idle);
    this.idle = null;
    while (!this.steps.next().done);
    overlay.prepend(this.layer);
    const { scrollTop, scrollLeft } = document.documentElement;
    for (const { page, root } of this.shards) {
      this.restoreScroll(page, root, `${scrollTop} ${scrollLeft}`);
      // The button went down after the page was copied.
      root
        .querySelector(".fabricate-promo__card")
        ?.classList.add("fabricate-promo__card--pressed");
    }
  }

  // A crack along every ray, plus a broken ring round the origin.
  drawCracks(rays) {
    const { x, y } = this.origin;
    const reach = Math.hypot(window.innerWidth, window.innerHeight);
    const lines = rays.map((angle) => {
      let path = `M${x} ${y}`;
      for (let r = 60; r < reach; r += 80 + Math.random() * 120) {
        const wobble = angle + (Math.random() - 0.5) * 0.08;
        path += ` L${x + Math.cos(wobble) * r} ${y + Math.sin(wobble) * r}`;
      }
      return path;
    });
    const ring = rays.map((angle) => {
      const r = 70 + Math.random() * 50;
      return `${x + Math.cos(angle) * r} ${y + Math.sin(angle) * r}`;
    });
    lines.push(`M${ring.join(" L")} Z`);

    const svg = document.createElementNS(SVG, "svg");
    svg.classList.add("fabricate-shatter__cracks");
    for (const d of lines) {
      const path = document.createElementNS(SVG, "path");
      path.setAttribute("d", d);
      path.setAttribute("pathLength", "1");
      path.style.strokeDasharray = "1";
      path.style.strokeDashoffset = "1";
      svg.append(path);
    }
    return svg;
  }

  // The wedge between two rays, with its share of the cracks.
  cutShard(from, to, cracks) {
    const { x, y } = this.origin;
    const far = Math.hypot(window.innerWidth, window.innerHeight) * 2;
    const point = (angle) =>
      `${x + Math.cos(angle) * far}px ${y + Math.sin(angle) * far}px`;
    const element = document.createElement("div");
    element.className = "fabricate-shatter__shard";
    element.style.clipPath = `polygon(${x}px ${y}px, ${point(from)}, ${point((from + to) / 2)}, ${point(to)})`;
    const { page, root } = this.copyPage();
    element.append(page, cracks.cloneNode(true));
    this.pieces.append(element);

    // Flung out from the origin, up a little, then left to gravity, spinning about its middle.
    const { minSpeed, maxSpeed, kick, spin } = timeline.shatter;
    const mid = (from + to) / 2;
    element.style.transformOrigin = `${x + Math.cos(mid) * 300}px ${y + Math.sin(mid) * 300}px`;
    const speed = minSpeed + Math.random() * (maxSpeed - minSpeed);
    return {
      element,
      page,
      root,
      vx: Math.cos(mid) * speed,
      vy: Math.sin(mid) * speed - kick,
      spin: (Math.random() - 0.5) * spin,
    };
  }

  // A lifeless copy of the page: no controllers, frames or scripts that would wake up in it. It
  // sits in a closed shadow root, with the page's stylesheets, so that extensions watching the
  // page don't see tens of thousands of new nodes arrive at the click: 1Password froze Firefox
  // for a second scanning them.
  copyPage() {
    const page = document.createElement("div");
    page.className = "fabricate-shatter__page";
    page.style.background = getComputedStyle(
      document.documentElement,
    ).backgroundColor;
    const root = page.attachShadow({ mode: "closed" });
    root.append(
      ...this.stylesheets.map((sheet) => sheet.cloneNode(true)),
      this.template.cloneNode(true),
    );
    return { page, root };
  }

  snapshot() {
    this.stylesheets = [
      ...document.head.querySelectorAll('link[rel="stylesheet"], style'),
    ];
    const scrolled = [...document.body.querySelectorAll("*")].filter(
      (element) => element.scrollTop || element.scrollLeft,
    );
    for (const element of scrolled)
      element.dataset.fabricateScroll = `${element.scrollTop} ${element.scrollLeft}`;
    const copy = document.body.cloneNode(true);
    for (const element of scrolled) delete element.dataset.fabricateScroll;

    copy
      .querySelectorAll(
        "script, iframe, turbo-cable-stream-source, .fabricate-promo__overlay",
      )
      .forEach((element) => element.remove());
    // Lazy frames that have already loaded, like the feed, stay in the picture but never fetch.
    for (const frame of copy.querySelectorAll("turbo-frame")) {
      frame.removeAttribute("src");
      frame.removeAttribute("loading");
    }
    for (const element of [copy, ...copy.querySelectorAll("*")]) {
      element.removeAttribute("id");
      for (const { name } of [...element.attributes]) {
        if (/^data-(controller|action|turbo)/.test(name))
          element.removeAttribute(name);
      }
    }
    return copy;
  }

  // The page scrolls on <html>, which the copy doesn't have; its scroll lands on the copy's
  // wrapper instead.
  restoreScroll(page, root, pageScroll) {
    const scroll = (element, value) => {
      const [top, left] = value.split(" ").map(Number);
      element.scrollTop = top;
      element.scrollLeft = left;
    };
    scroll(page, pageScroll);
    for (const element of root.querySelectorAll("[data-fabricate-scroll]"))
      scroll(element, element.dataset.fabricateScroll);
  }

  // The shattered page `time` seconds into the strike. Until the crack it's hidden over the real
  // page; then the cracks race out from the origin, the pieces shake, and from the fall they fly
  // apart under gravity.
  at(time) {
    const { crack, fall } = timeline.cues;
    const { crackMs, fallMs, shakeMs, shakePx, gravity } = timeline.shatter;
    this.layer.classList.toggle("fabricate-shatter--cracked", time >= crack);
    const drawn = crackMs ? (time - crack) / (crackMs / 1000) : 1;
    this.paths ??= this.layer.querySelectorAll(
      ".fabricate-shatter__cracks path",
    );
    for (const path of this.paths)
      path.style.strokeDashoffset = 1 - Math.min(1, Math.max(0, drawn));
    applyJolt(this.pieces, joltAt(time - crack, shakeMs / 1000, shakePx));

    const t = Math.min(Math.max(0, time - fall), fallMs / 1000);
    for (const { element, vx, vy, spin } of this.shards) {
      const x = vx * t;
      const y = vy * t + (gravity * t * t) / 2;
      element.style.transform = `translate(${x}px, ${y}px) rotate(${spin * t}deg)`;
    }
  }

  destroy() {
    if (this.idle) cancelIdle(this.idle);
    this.idle = null;
    this.layer.remove();
  }
}

// Rays out from the origin at uneven angles, in order round the circle.
function castRays() {
  const { minShards, maxShards } = timeline.shatter;
  const count =
    minShards + Math.floor(Math.random() * (maxShards - minShards + 1));
  const step = (Math.PI * 2) / count;
  const start = Math.random() * step;
  return Array.from(
    { length: count },
    (_, i) => start + i * step + (Math.random() - 0.5) * step * 0.6,
  );
}
