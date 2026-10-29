import { Controller } from "@hotwired/stimulus";
import BlastDoor from "../fabricate_promo/blast_door";
import Cutscene from "../fabricate_promo/cutscene";
import DoorSounds from "../fabricate_promo/door_sounds";
import { cancelIdle, whenIdle } from "../fabricate_promo/idle";
import RocketStrike from "../fabricate_promo/rocket_strike";
import Shatter from "../fabricate_promo/shatter";
import StrikeShow from "../fabricate_promo/strike_show";

export default class extends Controller {
  static targets = ["card", "door"];
  static values = {
    url: String,
    cutscene: Boolean,
    strikeWebm: String,
    strikeMp4: String,
    shatterSound: String,
    pipeSound: String,
  };

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.onPageShow = (event) => {
      if (event.persisted) this.reset();
    };
    window.addEventListener("pageshow", this.onPageShow);
  }

  disconnect() {
    window.removeEventListener("pageshow", this.onPageShow);
    this.reset();
    this.discardPrepared();
  }

  // As soon as the button looks likely to be pressed, start loading the rocket clip, and in idle
  // moments cut the page into shards and set up WebGL, so the click has little left to do. Each
  // is done in short steps, so none of them holds up a frame for long. The sounds wait for the
  // click: an AudioContext made before one is slower to create than the click saves.
  warm() {
    if (this.reduceMotion || this.cutsceneValue) return;
    this.clip ??= RocketStrike.preload({
      webm: this.strikeWebmValue,
      mp4: this.strikeMp4Value,
    });
    if (this.shatter?.stale) {
      this.shatter.destroy();
      this.shatter = null;
    }
    this.shatter ??= new Shatter();
    this.shatter.prebuild();
    this.preparing ??= whenIdle(() => {
      this.strike ??= new RocketStrike(this.clip);
    });
  }

  // Drops whatever was built ahead of a click.
  discardPrepared() {
    if (this.preparing) cancelIdle(this.preparing);
    this.shatter?.destroy();
    this.strike?.destroy();
    this.preparing = this.shatter = this.strike = null;
  }

  async launch(event) {
    if (this.reduceMotion) return;
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    event.preventDefault();
    if (this.launching) return;
    // Count now, even if the visitor leaves during the animation. The final
    // navigation bypasses this endpoint so the click is only recorded once.
    fetch(this.cardTarget.href, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      cache: "no-store",
      keepalive: true,
    }).catch(() => {
      // Don't retry: the server may have counted a request whose response failed.
    });
    await this.play();
    // Unless the show was torn down partway, by leaving the page say. Fabricate opens the door.
    if (this.launching) window.location.assign(this.doorUrl);
  }

  // Fabricate's landing page, told to draw the shut door over itself and open it.
  get doorUrl() {
    const url = new URL(this.urlValue);
    url.searchParams.set("door", "stardance");
    return url.toString();
  }

  // The whole show, from the button going down to the door unlocking.
  async play() {
    this.stage();
    if (this.cutscene) {
      await this.cutscene.play();
    } else {
      await this.show.prepare();
      await this.show.play();
    }
  }

  // Puts the show up over the page without starting it.
  stage() {
    this.launching = true;
    this.cardTarget.classList.add("fabricate-promo__card--pressed");
    this.sounds = new DoorSounds({
      shatter: this.shatterSoundValue,
      pipe: this.pipeSoundValue,
    });
    this.sounds.press();
    this.door = new BlastDoor(this.doorTarget, this.sounds);
    if (this.cutsceneValue) {
      this.cutscene = new Cutscene(this.door, this.sounds);
      this.cutscene.lock();
    }
    this.door.mount();
    if (!this.cutscene) {
      // The rocket comes down on the page and smashes it, and the doors slam shut while the
      // pieces are still falling.
      this.warm();
      this.strike ??= new RocketStrike(this.clip);
      this.show = new StrikeShow({
        door: this.door,
        sounds: this.sounds,
        strike: this.strike,
        shatter: this.shatter,
      });
    }
  }

  // Coming back through the back/forward cache restores the page mid-strike.
  reset() {
    if (!this.launching) return;
    this.cutscene?.destroy();
    this.show?.destroy();
    this.door?.destroy();
    this.sounds?.close();
    this.discardPrepared();
    this.cutscene = this.show = this.door = this.sounds = this.clip = null;
    this.cardTarget.classList.remove("fabricate-promo__card--pressed");
    this.launching = false;
  }
}
