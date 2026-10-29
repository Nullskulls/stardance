// Every tunable timing, position and volume in the rocket strike, kept in timeline.json:
// - speed: playback rate of the whole thing, clip included.
// - impact: where the rocket's explosion lands, as fractions of the viewport. The page shatters
//   from shatter.x and shatter.y, set separately.
// - cues: seconds into the rocket clip at which each beat fires. They run on the clip's clock, so
//   speed scales them along with it.
// - clip: fades on the rocket clip's picture and its own sound. fadeOutAt and soundFadeOutAt are
//   seconds into the clip, the rest ms at speed 1. The clip is 3.97s long.
// - shatter, door: durations in ms at speed 1, shard counts, distances in px, gravity in px/s².
//   door.pipeDelayMs is when the metal pipe drops relative to the leaves meeting, so it stays on
//   the slam whatever the clip is doing.
// - volume: gain for the clip's sound (at most 1), the synthesised door sounds and each recorded
//   sample.
import timeline from "./timeline.json";

export default timeline;
