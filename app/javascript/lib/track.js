window.Stardance = window.Stardance || {};

window.Stardance.track = function (name, props) {
  props = props || {};

  if (typeof FS !== "undefined" && FS.event) {
    FS.event(name, props);
  }

  if (typeof plausible !== "undefined") {
    plausible(name, { props: props });
  }

  if (typeof gtag !== "undefined") {
    gtag("event", name, props);
  }
};
