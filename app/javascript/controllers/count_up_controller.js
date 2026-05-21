import { Controller } from "@hotwired/stimulus";

// Smooth count-up: each frame computes the eased current value and writes it
// to textContent. No per-digit animation, no slot machinery — just a clean
// number ticker that respects prefers-reduced-motion.
export default class extends Controller {
  static values = {
    target: Number,
    duration: { type: Number, default: 1800 },
    start: { type: Number, default: 0 },
  };

  connect() {
    const reducedMotion =
      window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    if (reducedMotion) {
      this.element.textContent = this.#format(this.targetValue);
      return;
    }

    this.startTime = performance.now();
    this.element.textContent = this.#format(this.startValue);
    this.#tick();
  }

  #tick() {
    const elapsed = performance.now() - this.startTime;
    const progress = Math.min(elapsed / this.durationValue, 1);
    const eased = 1 - Math.pow(1 - progress, 5);
    const value = Math.round(
      this.startValue + (this.targetValue - this.startValue) * eased,
    );

    this.element.textContent = this.#format(value);

    if (progress < 1) requestAnimationFrame(() => this.#tick());
  }

  #format(n) {
    return n.toLocaleString();
  }
}
