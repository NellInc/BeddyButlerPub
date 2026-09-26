"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const statuses = new Map();
const retries = new Map();
const toggles = new Map();
const players = ["shy", "insistent", "zombie"].map(name => {
  const id = `sample-${name}`;
  statuses.set(`${id}-status`, { textContent: "" });
  toggles.set(`${id}-toggle`, { hidden: true, textContent: "▶ Hear sample", attributes: {}, handlers: {},
    setAttribute(k, v) { this.attributes[k] = v; },
    addEventListener(k, f) { this.handlers[k] = f; }
  });
  retries.set(id, { hidden: true, handlers: {}, addEventListener(k, f) { this.handlers[k] = f; } });
  return { id, error: null, ended: false, paused: true, handlers: {},
    addEventListener(k, f) { const prior = this.handlers[k]; this.handlers[k] = () => { prior?.(); f(); }; },
    // Browser order: pause() fires "pause", then rejects a still-pending play() with AbortError.
    pause() {
      this.paused = true; this.handlers.pause?.();
      const pending = this.pending; this.pending = null;
      pending?.reject(Object.assign(new Error("The play() request was interrupted by a call to pause()."), { name: "AbortError" }));
    },
    load() { this.error = null; },
    play() {
      this.paused = false; this.handlers.play();
      return new Promise((resolve, reject) => {
        const entry = { reject };
        this.pending = entry;
        queueMicrotask(() => { if (this.pending === entry) { this.pending = null; resolve(); } });
      });
    }
  };
});
const docHandlers = {}, winHandlers = {};
const document = {
  hidden: false,
  querySelectorAll: () => players,
  getElementById: id => statuses.get(id) || toggles.get(id),
  querySelector: selector => retries.get(selector.match(/data-player="([^"]+)"/)[1]),
  addEventListener(k, f) { docHandlers[k] = f; }
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,"../Website/assets/samples.js"), "utf8"), {
  document, window: { addEventListener(k,f) { winHandlers[k] = f; } }
});
const settle = async () => { for (let i = 0; i < 4; i++) await Promise.resolve(); };
const quiet = id => statuses.get(`${id}-status`).textContent === "" && retries.get(id).hidden;
(async () => {
  assert.ok(players.every(p => p.paused && p.volume === 0.5));
  assert.ok(players.every(p => p.hidden));
  assert.ok([...toggles.values()].every(t => !t.hidden));
  const shyToggle = toggles.get("sample-shy-toggle");
  shyToggle.handlers.click();
  assert.equal(players[0].paused, false);
  assert.equal(shyToggle.textContent, "Ⅱ Pause sample");
  assert.equal(shyToggle.attributes["aria-label"], "Pause sample, Shy");
  shyToggle.handlers.click();
  assert.equal(players[0].paused, true);
  assert.equal(shyToggle.textContent, "▶ Hear sample");
  shyToggle.handlers.click();
  toggles.get("sample-insistent-toggle").handlers.click();
  assert.equal(shyToggle.attributes["aria-label"], "Hear sample, Shy");
  assert.equal(toggles.get("sample-insistent-toggle").attributes["aria-label"], "Pause sample, Insistent");
  assert.ok(players[0].paused && !players[1].paused && players[2].paused);
  // Switching samples and double-toggling while play() is still pending is not a failure.
  await settle();
  assert.ok(quiet("sample-shy") && quiet("sample-insistent"));
  toggles.get("sample-insistent-toggle").handlers.click();
  shyToggle.handlers.click();
  toggles.get("sample-zombie-toggle").handlers.click();
  await settle();
  assert.ok(players[0].paused && players[1].paused && !players[2].paused);
  assert.ok(players.every(p => quiet(p.id)));
  toggles.get("sample-zombie-toggle").handlers.click();
  toggles.get("sample-zombie-toggle").handlers.click();
  toggles.get("sample-zombie-toggle").handlers.click();
  await settle();
  assert.ok(players[2].paused && quiet("sample-zombie"));
  retries.get("sample-shy").handlers.click();
  winHandlers.pagehide();
  await settle();
  assert.ok(players.every(p => p.paused && quiet(p.id)));
  players[1].error = { code: 4 }; players[1].handlers.error();
  assert.match(statuses.get("sample-insistent-status").textContent, /could not play/);
  assert.equal(retries.get("sample-insistent").hidden, false);
  retries.get("sample-insistent").handlers.click();
  assert.equal(retries.get("sample-insistent").hidden, true);
  document.hidden = true; docHandlers.visibilitychange();
  assert.ok(players.every(p => p.paused));
  await players[0].play(); winHandlers.pagehide();
  assert.ok(players.every(p => p.paused));
  players[2].play = () => Promise.reject(new Error("unsupported format"));
  toggles.get("sample-zombie-toggle").handlers.click();
  await settle();
  assert.match(statuses.get("sample-zombie-status").textContent, /could not play/);
  assert.equal(retries.get("sample-zombie").hidden, false);
  console.log("Audio controller passed: custom button wiring and labels, no autoplay, exclusive playback, errors, retry/rejection, no false error on pause/switch while loading, hidden-tab and page-exit pause.");
})().catch(error => { console.error(error); process.exitCode = 1; });
