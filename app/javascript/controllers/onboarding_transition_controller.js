import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { duration: { type: Number, default: 700 } };

  connect() {
    this.onSubmitStart = (event) => {
      if (!this.element.contains(event.target)) return;
      this.element.classList.add("is-leaving");
    };

    document.addEventListener("turbo:submit-start", this.onSubmitStart);
  }

  disconnect() {
    document.removeEventListener("turbo:submit-start", this.onSubmitStart);
  }

  leave(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1)
      return;
    event.preventDefault();
    const target = event.currentTarget;
    const href =
      target.getAttribute("href") || target.getAttribute("data-href");
    if (!href) return;

    this.element.classList.add("is-leaving");

    setTimeout(() => {
      if (window.Turbo) {
        window.Turbo.visit(href);
      } else {
        window.location.href = href;
      }
    }, this.durationValue);
  }

  press(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const form = button.form || button.closest("form");
    if (!form) return;

    const siblings = Array.from(
      form.querySelectorAll("button[type=submit]"),
    ).filter((b) => b !== button);

    if (siblings.length > 0) {
      // Multi-option: fade siblings, brief hold, then fade selected + page
      const OTHERS_OUT = 350;
      const HOLD = 250;
      const SELECTED_OUT = 650;

      siblings.forEach((s) => s.classList.add("is-fading-out"));

      setTimeout(() => {
        button.classList.add("is-fading-out");
        this.element.classList.add("is-leaving");
      }, OTHERS_OUT + HOLD);

      setTimeout(
        () => {
          if (typeof form.requestSubmit === "function") {
            form.requestSubmit(button);
          } else {
            form.submit();
          }
        },
        OTHERS_OUT + HOLD + SELECTED_OUT,
      );
    } else {
      // Solo button: just fade the page out, then submit
      this.element.classList.add("is-leaving");
      setTimeout(() => {
        if (typeof form.requestSubmit === "function") {
          form.requestSubmit(button);
        } else {
          form.submit();
        }
      }, 650);
    }
  }
}
