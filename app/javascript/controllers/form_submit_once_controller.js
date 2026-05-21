import { Controller } from "@hotwired/stimulus";

// Prevents accidental duplicate submissions (double-click, network retry, F5
// during in-flight POST). Disables the form's submit button(s) after the first
// submit event fires.
export default class extends Controller {
  connect() {
    this.submitted = false;
    this.element.addEventListener("submit", this.onSubmit);
  }

  disconnect() {
    this.element.removeEventListener("submit", this.onSubmit);
  }

  onSubmit = (event) => {
    if (this.submitted) {
      event.preventDefault();
      return;
    }
    this.submitted = true;

    // Defer the disable so the browser has already started the form submission.
    // Disabling a button synchronously inside the submit handler can cancel
    // the submission in some browsers.
    queueMicrotask(() => {
      const buttons = this.element.querySelectorAll(
        "button[type=submit], input[type=submit]",
      );
      buttons.forEach((b) => {
        b.disabled = true;
        b.classList.add("is-submitting");
      });
    });
  };
}
