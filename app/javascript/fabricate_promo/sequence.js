// A clock for a stretch of the Fabricate ad that can be played, paused and sought. Time is in
// seconds at speed 1; playing advances it at timeline.speed. Each frame `render(time, playing)`
// draws everything as it stands at that moment, so seeking backwards is as good as forwards.
// Events ({ at, run }) are the one-off moments, sounds mostly: they fire as playback passes them,
// never on a seek. `to` and `events` can be functions, read afresh every frame, so a timeline
// being edited takes effect as it plays. `follow`, if given, can hand the clock over to something
// with a mind of its own, like a playing video: it returns the time, or null to let the clock run.
import timeline from "./timeline";

export default class Sequence {
  constructor({ from = 0, to, render, events = [], follow, onPlay, onPause }) {
    this.start = from;
    this.time = from;
    this.to = to;
    this.render = render;
    this.eventsFrom = events;
    this.follow = follow;
    this.onPlay = onPlay;
    this.onPause = onPause;
  }

  get playing() {
    return !!this.frame;
  }

  get end() {
    return typeof this.to === "function" ? this.to() : this.to;
  }

  get events() {
    return typeof this.eventsFrom === "function"
      ? this.eventsFrom()
      : this.eventsFrom;
  }

  get finished() {
    return this.time >= this.end;
  }

  // Resolves when it reaches the end or is paused.
  play() {
    if (this.playing) return this.stopped;
    if (this.finished) this.time = this.start;
    this.onPlay?.();
    this.stopped = new Promise((resolve) => (this.resolve = resolve));
    let last;
    const tick = (now) => {
      const from = this.time;
      if (last != null) {
        const followed = this.follow?.();
        this.time = Math.min(
          this.end,
          followed ?? from + ((now - last) / 1000) * timeline.speed,
        );
      }
      last = now;
      for (const event of this.events)
        if (event.at >= from && event.at < this.time) event.run();
      this.render(this.time, true);
      if (this.finished) this.pause();
      else this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
    return this.stopped;
  }

  pause() {
    if (!this.playing) return;
    cancelAnimationFrame(this.frame);
    this.frame = null;
    this.onPause?.();
    this.render(this.time, false);
    this.resolve();
  }

  seek(time) {
    this.time = Math.min(this.end, Math.max(this.start, time));
    this.render(this.time, this.playing);
  }
}
