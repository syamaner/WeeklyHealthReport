const $ = (selector) => document.querySelector(selector);
let state;
let current = 0;
let openedAt = Date.now();
let baseSeconds = 0;
let scale = 1;
let rotation = 0;

const bases = ["per_100g", "per_100ml", "per_serving", "reference_intake"];
const comparators = ["", "<", "<="];

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>'"]/g, char => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));
}

function optionList(values, selected) {
  return values.map(value => `<option value="${escapeHTML(value)}" ${value === (selected ?? "") ? "selected" : ""}>${escapeHTML(value || "—")}</option>`).join("");
}

function emptyCell() {
  return {row_id:"", parent_row_id:null, header_id:"header_1", basis:"per_100g", printed_text:"", comparator:null, decimal_text:"", unit:"g", serving_conversion:null};
}

function addCell(cell = emptyCell()) {
  const row = document.createElement("tr");
  row.innerHTML = `
    <td><input data-key="row_id" value="${escapeHTML(cell.row_id)}"></td>
    <td><input data-key="parent_row_id" value="${escapeHTML(cell.parent_row_id ?? "")}"></td>
    <td><input data-key="header_id" value="${escapeHTML(cell.header_id)}"></td>
    <td><select data-key="basis">${optionList(bases, cell.basis)}</select></td>
    <td><input data-key="printed_text" value="${escapeHTML(cell.printed_text)}"></td>
    <td><select data-key="comparator">${optionList(comparators, cell.comparator ?? "")}</select></td>
    <td><input data-key="decimal_text" value="${escapeHTML(cell.decimal_text)}"></td>
    <td><input data-key="unit" value="${escapeHTML(cell.unit)}"></td>
    <td><input data-key="serving_conversion" value="${escapeHTML(cell.serving_conversion ?? "")}"></td>
    <td><button class="remove" type="button">×</button></td>`;
  row.querySelector(".remove").addEventListener("click", () => row.remove());
  $("#cells").appendChild(row);
}

function cellsFromForm() {
  return [...$("#cells").querySelectorAll("tr")].map(row => {
    const value = {};
    row.querySelectorAll("[data-key]").forEach(input => value[input.dataset.key] = input.value);
    value.parent_row_id = value.parent_row_id || null;
    value.comparator = value.comparator || null;
    value.serving_conversion = value.serving_conversion || null;
    return value;
  });
}

function currentPanel() { return state.panels[current]; }

function draftFor(panel) {
  if (panel.annotation) return panel.annotation;
  if (panel.assistant_draft) return panel.assistant_draft;
  return {
    reviewer: localStorage.getItem("issue88-reviewer") || "",
    full_transcript: panel.draft_transcript,
    cells: panel.draft_cells,
    families: panel.proposed_families,
    requires_decline: false,
    decline_reason: "",
    verification_assertion: false,
    correction_seconds: 0,
    started_at: new Date().toISOString(),
  };
}

function render() {
  const panel = currentPanel();
  const value = draftFor(panel);
  $("#review-label").textContent = state.review_label;
  $("#review-description").textContent = state.review_description;
  document.title = `${state.review_label} · nutrition-panel review`;
  openedAt = Date.now();
  baseSeconds = Number(value.correction_seconds || 0);
  scale = 1;
  rotation = 0;
  $("#panel-number").textContent = `Panel ${panel.review_index} of ${state.frozen_total || state.panels.length}${panel.annotation ? " · reviewed" : panel.assistant_draft ? " · assistant candidate" : ""}`;
  $("#product-name").textContent = panel.product_name || "Unnamed product";
  $("#product-code").textContent = `Product ${panel.product_code} · image ${panel.image_sha256.slice(0, 12)}…`;
  $("#draft-source").textContent = panel.assistant_draft && !panel.annotation
    ? `Draft: assistant candidate, pending your visual confirmation. ${panel.assistant_draft.review_notes || ""}`
    : `Draft: ${panel.draft_source}`;
  $("#panel-image").src = panel.image_path;
  applyImageTransform();
  $("#reviewer").value = value.reviewer || localStorage.getItem("issue88-reviewer") || "";
  $("#transcript").value = value.full_transcript || "";
  $("#cells").innerHTML = "";
  (value.cells || []).forEach(addCell);
  $("#families").innerHTML = state.families.map(family => `<label><input type="checkbox" value="${family}" ${(value.families || []).includes(family) ? "checked" : ""}> ${family.replaceAll("_", " ")}</label>`).join("");
  $("#requires-decline").checked = Boolean(value.requires_decline);
  $("#decline-reason").value = value.decline_reason || "";
  $("#verified").checked = Boolean(value.verification_assertion && panel.annotation);
  $("#previous").disabled = current === 0;
  setStatus(panel.annotation ? "Saved review loaded" : panel.assistant_draft ? "Assistant candidate saved separately—not human-verified. Check every value against the image before saving." : "Unsaved machine draft—verify everything", false);
  updateProgress();
}

function applyImageTransform() {
  $("#panel-image").style.transform = `scale(${scale}) rotate(${rotation}deg)`;
}

function setStatus(message, error = false) {
  $("#status").textContent = message;
  $("#status").classList.toggle("error", error);
}

function updateProgress() {
  const reviewed = state.panels.filter(panel => panel.annotation).length;
  const prepared = state.panels.filter(panel => panel.assistant_draft && !panel.annotation).length;
  $("#progress").textContent = `${reviewed} / ${state.panels.length} in review queue · ${prepared} assistant candidates${state.excluded_count ? ` · ${state.excluded_count} excluded from frozen ${state.frozen_total}` : ""}`;
  $("#progress-bar").style.width = `${reviewed / state.panels.length * 100}%`;
  const counts = Object.fromEntries(state.families.map(family => [family, 0]));
  state.panels.forEach(panel => (panel.annotation?.families || []).forEach(family => counts[family]++));
  $("#coverage").innerHTML = state.families.map(family => `<span class="${counts[family] ? "covered" : ""}">${family.replaceAll("_", " ")}: ${counts[family]}</span>`).join("");
}

async function save() {
  if ($("#save").disabled) return;
  const panel = currentPanel();
  const reviewer = $("#reviewer").value.trim();
  localStorage.setItem("issue88-reviewer", reviewer);
  const payload = {
    panel_id: panel.panel_id,
    image_sha256: panel.image_sha256,
    reviewer,
    started_at: panel.annotation?.started_at || new Date(openedAt).toISOString(),
    correction_seconds: baseSeconds + (Date.now() - openedAt) / 1000,
    full_transcript: $("#transcript").value,
    cells: cellsFromForm(),
    families: [...$("#families").querySelectorAll("input:checked")].map(input => input.value),
    requires_decline: $("#requires-decline").checked,
    decline_reason: $("#decline-reason").value,
    verification_assertion: $("#verified").checked,
  };
  setStatus("Saving…");
  $("#save").disabled = true;
  let saved = false;
  try {
    const response = await fetch("/api/annotation", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(payload)});
    const result = await response.json();
    if (!response.ok) {
      setStatus(result.error || "Save failed; your edits are still on this page. Try again.", true);
      return;
    }
    saved = true;
    state.panels[current].annotation = payload;
    updateProgress();
    const refreshed = await fetch("/api/state").then(value => value.json());
    state = refreshed;
    setStatus("Saved");
    const next = state.panels.findIndex((candidate, index) => index > current && !candidate.annotation);
    if (next >= 0) current = next;
    else if (current < state.panels.length - 1) current++;
    render();
  } catch (error) {
    setStatus(saved
      ? "Saved locally, but progress could not reload. Keep this page open and try again after the connection returns. (" + error.message + ")"
      : "Connection failed; your edits are still on this page. Check the local server, then try Save and next again. (" + error.message + ")", true);
  } finally {
    $("#save").disabled = false;
  }
}

$("#add-cell").addEventListener("click", () => addCell());
$("#save").addEventListener("click", save);
$("#previous").addEventListener("click", () => { if (current > 0) { current--; render(); } });
$("#show-incomplete").addEventListener("click", () => {
  const next = state.panels.findIndex(panel => !panel.annotation);
  if (next >= 0) { current = next; render(); }
});
document.querySelectorAll("[data-zoom]").forEach(button => button.addEventListener("click", () => {
  scale = Math.max(.4, Math.min(4, scale + (button.dataset.zoom === "in" ? .2 : -.2)));
  applyImageTransform();
}));
document.querySelectorAll("[data-rotate]").forEach(button => button.addEventListener("click", () => {
  rotation += button.dataset.rotate === "right" ? 90 : -90;
  applyImageTransform();
}));
$("#reset-image").addEventListener("click", () => { scale = 1; rotation = 0; applyImageTransform(); });
document.addEventListener("keydown", event => {
  if ((event.ctrlKey || event.metaKey) && event.key === "Enter") { event.preventDefault(); save(); }
});

fetch("/api/state").then(response => response.json()).then(value => { state = value; render(); }).catch(error => setStatus(`Cannot load review: ${error}`, true));
