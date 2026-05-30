import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["track", "left", "right"];

  connect() {
    this._onScroll = this._updateArrows.bind(this);
    this.trackTarget.addEventListener("scroll", this._onScroll, {
      passive: true,
    });
    this._ro = new ResizeObserver(() => this._updateArrows());
    this._ro.observe(this.trackTarget);
    this._updateArrows();
    // Re-check after images settle
    requestAnimationFrame(() => this._updateArrows());
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this._onScroll);
    this._ro.disconnect();
  }

  scrollLeft() {
    this.trackTarget.scrollBy({ left: -300, behavior: "smooth" });
  }

  scrollRight() {
    this.trackTarget.scrollBy({ left: 300, behavior: "smooth" });
  }

  _updateArrows() {
    const el = this.trackTarget;
    const atStart = el.scrollLeft <= 1;
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 1;

    if (this.hasLeftTarget) {
      this.leftTarget.dataset.visible = String(!atStart);
    }
    if (this.hasRightTarget) {
      this.rightTarget.dataset.visible = String(!atEnd);
    }

    let mask;
    if (atStart && atEnd) {
      mask = "none";
    } else if (atStart) {
      mask =
        "linear-gradient(to right, black calc(100% - 56px), transparent 100%)";
    } else if (atEnd) {
      mask =
        "linear-gradient(to left, black calc(100% - 56px), transparent 100%)";
    } else {
      mask =
        "linear-gradient(to right, transparent 0%, black 56px, black calc(100% - 56px), transparent 100%)";
    }
    // Apply mask to the wrapper (this.element) so it doesn't clip
    // stars/badges that overflow the card bounds.
    this.element.style.maskImage = mask;
    this.element.style.webkitMaskImage = mask;
  }
}
