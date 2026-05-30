import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "preview"];

  change() {
    const file = this.inputTarget.files?.[0];
    if (!file) return;
    this._previewImage().src = URL.createObjectURL(file);
    this.element.classList.remove("project-show__banner--empty");
    this.element.querySelector(".project-show__banner-placeholder")?.remove();
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
