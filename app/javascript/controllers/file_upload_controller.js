import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "preview"];

  change() {
    const file = this.inputTarget.files?.[0];
    if (!file) return;
    this._previewImage().src = URL.createObjectURL(file);
  }

  _previewImage() {
    if (this.hasPreviewTarget) return this.previewTarget;

    const wrapper = document.createElement("div");
    wrapper.className = "ship__upload-preview";
    const img = document.createElement("img");
    img.className = "ship__upload-image";
    img.alt = "";
    wrapper.appendChild(img);
    this.element.prepend(wrapper);
    return img;
  }
}
