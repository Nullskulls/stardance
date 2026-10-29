// Runs work while the browser has nothing else to do, so getting the ad ready ahead of the click
// never holds up the page. Safari has no requestIdleCallback; a short timeout still keeps each
// step off a busy frame.
const FALLBACK_MS = 50;

export const whenIdle =
  window.requestIdleCallback ?? ((run) => setTimeout(run, FALLBACK_MS));
export const cancelIdle = window.cancelIdleCallback ?? clearTimeout;
