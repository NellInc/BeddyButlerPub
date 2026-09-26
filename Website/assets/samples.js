"use strict";
// Original audio stays local to this site; playback always requires a user action.
const samples = [...document.querySelectorAll("audio")];
for (const sample of samples) {
  const status = document.getElementById(`${sample.id}-status`);
  const retry = document.querySelector(`[data-player="${sample.id}"]`);
  const say = message => { if (status) status.textContent = message; };
  const failed = () => {
    say("This sample could not play. Check your connection, then try again.");
    if (retry) retry.hidden = false;
  };
  // pause() while play() is pending rejects with AbortError; that is not a failure.
  const playFailed = error => { if (error?.name !== "AbortError") failed(); };
  const toggle = document.getElementById(`${sample.id}-toggle`);
  const persona = sample.id.replace("sample-", "");
  const title = persona.charAt(0).toUpperCase() + persona.slice(1);
  const updateToggle = () => {
    if (!toggle) return;
    toggle.textContent = sample.paused ? "▶ Hear sample" : "Ⅱ Pause sample";
    toggle.setAttribute("aria-label", `${sample.paused ? "Hear" : "Pause"} sample, ${title}`);
  };
  if (toggle) {
    toggle.hidden = false;
    sample.hidden = true;
    toggle.addEventListener("click", () => {
      if (sample.paused) sample.play().catch(playFailed);
      else sample.pause();
    });
    for (const event of ["play", "pause", "ended", "error"]) sample.addEventListener(event, updateToggle);
  }
  sample.volume = 0.5;
  sample.addEventListener("play", () => {
    for (const other of samples) if (other !== sample) other.pause();
    if (retry) retry.hidden = true;
    say("");
  });
  sample.addEventListener("pause", () => {
    if (!sample.error && !sample.ended) say("");
  });
  sample.addEventListener("ended", () => say(""));
  sample.addEventListener("error", failed);
  if (retry) retry.addEventListener("click", () => {
    say("Loading sample…");
    sample.load();
    sample.play().catch(playFailed);
  });
}
const pauseSamples = () => samples.forEach(sample => sample.pause());
window.addEventListener("pagehide", pauseSamples);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) pauseSamples();
});
