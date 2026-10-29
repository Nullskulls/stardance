// The whole rocket strike as one sequence: the clip comes in, the page shatters under it, and the
// blast door slams shut over the wreckage and unlocks. Everything is drawn from the one
// clock (seconds into the clip), so the show can be played, paused and scrubbed as a piece.
//
// Without WebGL there's no keying, so the clip and the shatter are skipped and the door starts
// straight away.
import Sequence from "./sequence";
import timeline from "./timeline";

export default class StrikeShow {
  // `strike` and `shatter` are built ahead of time, once the button has been hovered.
  constructor({ door, sounds, strike, shatter }) {
    this.door = door;
    this.sounds = sounds;
    this.strike = strike;
    if (this.strike.supported) {
      this.shatter = shatter;
      this.strike.mount(door.overlay);
      this.shatter.mount(door.overlay);
    } else {
      shatter.destroy();
    }
    this.sequence = new Sequence({
      to: () => this.length,
      render: (time, playing) => this.at(time, playing),
      events: () => this.events,
      follow: () => this.shatter && this.strike.clock,
      onPlay: () => this.sounds.resume(),
      onPause: () => this.sounds.suspend(),
    });
  }

  // When the door starts closing, in seconds into the show.
  get doorsAt() {
    return this.shatter ? timeline.cues.doors : 0;
  }

  // Waits for the clip, then draws the first frame. Call `play()` or `seek()` from there.
  async prepare() {
    if (this.shatter) await this.strike.ready();
    this.sequence.seek(0);
  }

  get length() {
    return this.doorsAt + this.door.length;
  }

  get events() {
    const strike = this.shatter
      ? [
          {
            at: timeline.cues.crack,
            run: () => navigator.vibrate?.([200, 60, 120]),
          },
          {
            at: timeline.cues.shatterSound,
            run: () => this.sounds.play("shatter"),
          },
        ]
      : [];
    const door = this.door.events.map(({ at, run }) => ({
      at: this.doorsAt + at,
      run,
    }));
    return [...strike, ...door];
  }

  at(time, playing) {
    if (this.shatter) {
      this.strike.at(time, playing);
      this.shatter.at(time);
    }
    this.door.at(time - this.doorsAt);
  }

  get time() {
    return this.sequence.time;
  }

  get playing() {
    return this.sequence.playing;
  }

  get finished() {
    return this.sequence.finished;
  }

  play() {
    return this.sequence.play();
  }

  pause() {
    this.sequence.pause();
  }

  seek(time) {
    this.sequence.seek(time);
  }

  destroy() {
    this.sequence.pause();
    this.shatter?.destroy();
    this.strike.destroy();
  }
}
