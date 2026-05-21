import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["trigger", "popover", "textarea"];

  #picker = null;
  #outsideClick = null;
  #escHandler = null;

  connect() {
    this.#outsideClick = (e) => {
      if (
        this.hasPopoverTarget &&
        !this.popoverTarget.contains(e.target) &&
        !this.triggerTarget.contains(e.target)
      ) {
        this.close();
      }
    };

    this.#escHandler = (e) => {
      if (e.key === "Escape") this.close();
    };
  }

  disconnect() {
    this.close();
    this.#picker = null;
  }

  toggle() {
    if (this.hasPopoverTarget && !this.popoverTarget.hidden) {
      this.close();
    } else {
      this.open();
    }
  }

  async open() {
    if (!this.hasPopoverTarget) return;

    if (!this.#picker) {
      const { Picker } = await import("emoji-mart");
      const data = (await import("@emoji-mart/data")).default;

      this.#picker = new Picker({
        data,
        onEmojiSelect: (emoji) => this.#insertEmoji(emoji),
        theme: "dark",
        set: "native",
        previewPosition: "none",
        skinTonePosition: "search",
        maxFrequentRows: 2,
      });

      this.popoverTarget.appendChild(this.#picker);
    }

    this.popoverTarget.hidden = false;
    document.addEventListener("click", this.#outsideClick, true);
    document.addEventListener("keydown", this.#escHandler);
  }

  close() {
    if (this.hasPopoverTarget) this.popoverTarget.hidden = true;
    document.removeEventListener("click", this.#outsideClick, true);
    document.removeEventListener("keydown", this.#escHandler);
  }

  #insertEmoji(emoji) {
    if (!this.hasTextareaTarget || !emoji.native) return;
    const ta = this.textareaTarget;
    const start = ta.selectionStart;
    const end = ta.selectionEnd;
    const before = ta.value.slice(0, start);
    const after = ta.value.slice(end);
    ta.value = before + emoji.native + after;
    const cursor = start + emoji.native.length;
    ta.setSelectionRange(cursor, cursor);
    ta.focus();
    ta.dispatchEvent(new Event("input", { bubbles: true }));
  }
}
