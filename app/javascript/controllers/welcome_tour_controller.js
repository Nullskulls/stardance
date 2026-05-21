import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["spotlight", "tooltip", "text", "back", "next", "counter"];

  static values = {
    step: { type: Number, default: 0 },
    steps: Array,
    minWidth: { type: Number, default: 900 },
  };

  connect() {
    if (window.innerWidth < this.minWidthValue) {
      this._abort();
      return;
    }

    this._onReflow = this._onReflow.bind(this);
    this._onKey = this._onKey.bind(this);

    window.addEventListener("resize", this._onReflow);
    window.addEventListener("scroll", this._onReflow, { passive: true });
    document.addEventListener("keydown", this._onKey);

    this._previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    this._render();
    requestAnimationFrame(() => {
      this.element.classList.add("welcome-tour--ready");
    });
  }

  disconnect() {
    window.removeEventListener("resize", this._onReflow);
    window.removeEventListener("scroll", this._onReflow);
    document.removeEventListener("keydown", this._onKey);
    if (this._previousOverflow !== undefined) {
      document.body.style.overflow = this._previousOverflow;
    }
  }

  stepValueChanged() {
    if (!this.hasSpotlightTarget) return;
    this._render();
  }

  next() {
    if (this.stepValue >= this.stepsValue.length - 1) {
      this.finish();
    } else {
      this.stepValue += 1;
    }
  }

  back() {
    if (this.stepValue > 0) this.stepValue -= 1;
  }

  finish() {
    this.element.remove();
  }

  _onReflow() {
    this._render();
  }

  _onKey(event) {
    if (event.key === "Escape") {
      this.finish();
    } else if (event.key === "ArrowRight") {
      this.next();
    } else if (event.key === "ArrowLeft") {
      this.back();
    }
  }

  _render() {
    const step = this.stepsValue[this.stepValue];
    if (!step) {
      this.finish();
      return;
    }

    this.element.classList.toggle("welcome-tour--intro", !!step.intro);

    if (step.intro) {
      this._renderIntro(step);
      return;
    }

    const target = this._findTarget(step.selector);
    if (!target) {
      if (this.stepValue < this.stepsValue.length - 1) {
        this.stepValue += 1;
      } else {
        this.finish();
      }
      return;
    }

    const pad = step.padding ?? 12;
    const rect = target.getBoundingClientRect();

    let top = rect.top - pad;
    const bottom = rect.bottom + pad;

    if (step.excludeTop) {
      const excluded = this._findTarget(step.excludeTop);
      if (excluded) {
        const excludedRect = excluded.getBoundingClientRect();
        const floor = excludedRect.bottom + (step.excludeGap ?? 0);
        if (floor > top) top = floor;
      }
    }

    const left = rect.left - pad;
    const width = rect.width + pad * 2;
    let height = bottom - top;
    if (step.maxHeight) {
      height = Math.min(height, step.maxHeight);
    }
    const radius = step.radius ?? 12;

    Object.assign(this.spotlightTarget.style, {
      top: `${top}px`,
      left: `${left}px`,
      width: `${width}px`,
      height: `${height}px`,
      borderRadius: `${radius}px`,
    });

    this.textTarget.textContent = step.text;
    this.counterTarget.textContent = `${this.stepValue + 1}/${this.stepsValue.length}`;

    const isLast = this.stepValue === this.stepsValue.length - 1;
    this.nextTarget.textContent = isLast
      ? "Finish! →"
      : `Next (${this.stepValue + 1}/${this.stepsValue.length}) →`;
    this.backTarget.hidden = this.stepValue === 0;

    this.element.classList.toggle(
      "welcome-tour--arrow-bottom",
      step.arrowPosition === "bottom",
    );
    this._positionTooltip(
      top,
      left,
      width,
      height,
      step.placement,
      step.arrowPosition,
    );
    this._applyPlacementClass(step.placement);
  }

  _applyPlacementClass(placement = "right") {
    this.element.classList.remove(
      "welcome-tour--placement-right",
      "welcome-tour--placement-left",
      "welcome-tour--placement-above",
      "welcome-tour--placement-below",
    );
    this.element.classList.add(
      `welcome-tour--placement-${this._lastResolvedPlacement || placement}`,
    );
  }

  _renderIntro(step) {
    Object.assign(this.spotlightTarget.style, {
      top: `${window.innerHeight / 2}px`,
      left: `${window.innerWidth / 2}px`,
      width: "0px",
      height: "0px",
      borderRadius: "0px",
    });

    this.textTarget.textContent = step.text;
    this.counterTarget.textContent = `${this.stepValue + 1}/${this.stepsValue.length}`;

    const isLast = this.stepValue === this.stepsValue.length - 1;
    this.nextTarget.textContent = isLast
      ? "Finish! →"
      : `Next (${this.stepValue + 1}/${this.stepsValue.length}) →`;
    this.backTarget.hidden = this.stepValue === 0;

    const tooltip = this.tooltipTarget;
    const tooltipRect = tooltip.getBoundingClientRect();
    Object.assign(tooltip.style, {
      top: `${Math.max(16, window.innerHeight / 2 - tooltipRect.height / 2)}px`,
      left: `${Math.max(16, window.innerWidth / 2 - tooltipRect.width / 2)}px`,
    });
  }

  _findTarget(selector) {
    for (const candidate of selector.split(",")) {
      const el = document.querySelector(candidate.trim());
      if (el) return el;
    }
    return null;
  }

  _positionTooltip(
    top,
    left,
    width,
    height,
    placement = "right",
    arrowPosition = "top",
  ) {
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const tooltip = this.tooltipTarget;
    const gap = 48;
    const minGap = 12;
    const margin = 16;
    const minWidth = 240;

    // Reset any prior width override so the tooltip measures at its natural size.
    tooltip.style.width = "";
    const naturalWidth = tooltip.getBoundingClientRect().width;

    const right = left + width;
    const bottom = top + height;

    const roomRight = vw - right - minGap - margin;
    const roomLeft = left - minGap - margin;

    const fitsRight = roomRight >= naturalWidth;
    const fitsLeft = roomLeft >= naturalWidth;
    const canShrinkRight = roomRight >= minWidth;
    const canShrinkLeft = roomLeft >= minWidth;

    let resolved = placement;
    if (placement === "right" && !fitsRight) {
      if (canShrinkRight) resolved = "right-shrink";
      else if (fitsLeft) resolved = "left";
      else if (canShrinkLeft) resolved = "left-shrink";
      else resolved = "below";
    }
    if (placement === "left" && !fitsLeft) {
      if (canShrinkLeft) resolved = "left-shrink";
      else if (fitsRight) resolved = "right";
      else if (canShrinkRight) resolved = "right-shrink";
      else resolved = "below";
    }
    if (placement === "above" || placement === "below") {
      resolved = placement;
    }

    let tooltipLeft;
    let tooltipTop;
    let appliedWidth = null;

    if (resolved === "left" || resolved === "left-shrink") {
      appliedWidth = resolved === "left-shrink" ? roomLeft : naturalWidth;
      tooltipLeft =
        left - appliedWidth - (resolved === "left-shrink" ? minGap : gap);
    } else if (resolved === "below") {
      appliedWidth = naturalWidth;
      tooltipLeft = left + width / 2 - appliedWidth / 2;
      tooltipTop = bottom + gap;
    } else if (resolved === "above") {
      appliedWidth = naturalWidth;
      tooltipLeft = left + width / 2 - appliedWidth / 2;
    } else {
      // right or right-shrink
      appliedWidth = resolved === "right-shrink" ? roomRight : naturalWidth;
      tooltipLeft = right + (resolved === "right-shrink" ? minGap : gap);
    }

    if (appliedWidth && appliedWidth !== naturalWidth) {
      tooltip.style.width = `${appliedWidth}px`;
    }

    const finalRect = tooltip.getBoundingClientRect();

    if (resolved === "above") {
      tooltipTop = top - gap - finalRect.height;
    } else if (resolved !== "below") {
      // Align the arrow's pointing end with the target's vertical center.
      // The arrow's tip is ~42px from whichever edge of the tooltip it sits on.
      const ARROW_TIP_OFFSET = 42;
      if (arrowPosition === "bottom") {
        tooltipTop = top + height / 2 - finalRect.height + ARROW_TIP_OFFSET;
      } else {
        tooltipTop = top + height / 2 - ARROW_TIP_OFFSET;
      }
    }

    this._lastResolvedPlacement = resolved.replace("-shrink", "");

    if (tooltipLeft < margin) tooltipLeft = margin;
    if (tooltipLeft + finalRect.width + margin > vw) {
      tooltipLeft = vw - finalRect.width - margin;
    }
    if (tooltipTop < margin) tooltipTop = margin;
    if (tooltipTop + finalRect.height + margin > vh) {
      tooltipTop = vh - finalRect.height - margin;
    }

    Object.assign(tooltip.style, {
      top: `${tooltipTop}px`,
      left: `${tooltipLeft}px`,
    });
  }

  _abort() {
    this.element.remove();
  }
}
