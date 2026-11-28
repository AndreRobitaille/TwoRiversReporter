import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.events = new AbortController()
    this.cleanUp = mount(this.element, this.events.signal)
  }

  disconnect() {
    this.events.abort()
    this.cleanUp?.()
  }
}

function mount(root, signal) {
  const $ = id => root.querySelector("#" + id)
  const colors = ["#526674", "#176478", "#7e4b91", "#35684b", "#945316", "#4059a3", "#a23458"]
  const defaultNames = JSON.parse(root.dataset.names)
  const defaultTitle = $("forum-title").value
  const defaultUrl = $("source-url").value
  let current, state, words = [], elements = [], selected = null, markedSelection = null
  let undoStack = [], redoStack = [], drag = null, selectionFrame = null, generation = 0
  const dragScrollPixelsPerSecond = 120

  function notify(message) {
    $("notice").textContent = message
    $("notice").hidden = !message
  }

  const transcript = $("transcript")
  let positionTimer
  function savePosition() {
    clearTimeout(positionTimer)
    if (!current) return
    const extent = transcript.scrollHeight - transcript.clientHeight
    if (extent <= 0) return
    try { localStorage.setItem(current.key + ":position", String(transcript.scrollTop / extent)) } catch { /* Optional bookmark. */ }
  }
  transcript.addEventListener("scroll", () => {
    clearTimeout(positionTimer)
    positionTimer = setTimeout(savePosition, 200)
  })
  window.addEventListener("pagehide", savePosition, { signal })

  function project() {
    return { format: "forum-speaker-desk", version: 1, parserVersion: 2,
      title: $("forum-title").value.trim(), sourceUrl: $("source-url").value.trim(),
      electionOn: $("forum_election_on").value, forumDate: $("forum_published_on").value,
      organizer: $("forum_publisher").value, coverageNotes: $("forum_coverage_notes").value,
      filename: current.filename, captions: current.raw, sourceSha256: current.hash,
      names: state.names, annotations: state.annotations, wordCount: words.length,
      transcriptionVerified: current.transcriptionVerified, timingBasis: current.timingBasis, savedAt: new Date().toISOString() }
  }

  function persist() {
    const data = project()
    delete data.captions
    try {
      localStorage.setItem(current.key, JSON.stringify(data))
      $("save-status").textContent = "Draft saved in this browser."
    } catch {
      $("save-status").textContent = "Browser storage is unavailable. Download a backup before leaving."
    }
  }

  function validate(data, count, hash) {
    if (data.format !== "forum-speaker-desk" || data.version !== 1 || ![1, 2].includes(data.parserVersion) ||
        data.sourceSha256 !== hash || data.wordCount !== count || !Array.isArray(data.names) || !data.names.length ||
        data.names.some(name => typeof name !== "string" || !name.trim()) || !Array.isArray(data.annotations)) {
      throw new Error("This project does not match its captions or speaker list.")
    }
    let previous = 0
    for (const {start, end, speaker} of data.annotations) {
      if (![start, end, speaker].every(Number.isInteger) || start < previous || end <= start || end > count ||
          speaker < 0 || speaker >= data.names.length) throw new Error("The project contains invalid speaker ranges.")
      previous = end
    }
  }

  async function activate(ticket, raw, filename, restored = null, resumingSavedSource = false) {
    if (ticket !== generation) return
    notify("Reading timestamped captions…")
    const form = new FormData()
    form.append("captions", new Blob([raw], { type: "text/plain" }), filename)
    const response = await fetch(root.dataset.preview, { method: "POST", body: form, signal,
      headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" } })
    if (ticket !== generation) return
    if (!response.headers.get("Content-Type")?.includes("application/json")) throw new Error("Sign in again, then reopen your captions.")
    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "Could not read the captions.")
    const key = ["forum-desk", root.dataset.user, data.hash, root.dataset.version].filter(Boolean).join(":")
    if (!restored || resumingSavedSource) {
      try { restored = JSON.parse(localStorage.getItem(key)) || restored } catch { /* Backups still work without local storage. */ }
    }
    if (restored) validate(restored, data.words.length, data.hash)
    if (ticket !== generation) return
    finishDrag()
    savePosition()
    current = { raw, filename, hash: data.hash, key, transcriptionVerified: restored?.transcriptionVerified === true,
                timingBasis: restored?.timingBasis || "Caption timings" }
    words = data.words.map(word => ({ text: word.text, start: word.start_ms / 1000, end: word.end_ms / 1000 }))
    const differentRecording = restored && restored.sourceUrl !== defaultUrl
    for (const [id, field] of [["forum_election_on", "electionOn"], ["forum_published_on", "forumDate"],
                                ["forum_publisher", "organizer"], ["forum_coverage_notes", "coverageNotes"]]) {
      const input = $(id)
      input.value = restored?.[field] ?? (differentRecording ? "" : input.defaultValue)
    }
    $("forum_speaker_verified").checked = false
    $("forum_gaps_are_moderator").checked = resumingSavedSource && root.dataset.moderator === "true"
    state = { names: restored?.names || [...defaultNames], annotations: restored?.annotations || [] }
    $("forum-title").value = restored?.title || defaultTitle || filename
    $("source-url").value = restored?.sourceUrl || defaultUrl
    selected = markedSelection = null
    undoStack = []
    redoStack = []
    $("work").hidden = false
    $("desk-files").hidden = true
    $("manage-files").setAttribute("aria-expanded", "false")
    $("save").disabled = false
    $("reading-title").textContent = $("forum-title").value
    const picker = $("recording-switch")
    if (picker) picker.value = [...picker.options].find(option => option.dataset.url === $("source-url").value)?.value || ""
    renderNames()
    renderTranscript()
    renderSpeakers()
    updateLabels()
    transcript.scrollTop = 0
    try {
      const ratio = Number(localStorage.getItem(key + ":position"))
      if (ratio > 0 && ratio <= 1) transcript.scrollTop = ratio * (transcript.scrollHeight - transcript.clientHeight)
    } catch { /* The recording is still ready to label. */ }
    $("save-status").textContent = restored && state.annotations.length && !resumingSavedSource
      ? "Draft reopened. Changes save in this browser." : "Changes save in this browser as you label."
    notify("")
  }

  function report(error) {
    if (signal.aborted) return
    $("desk-files").hidden = false
    $("manage-files").setAttribute("aria-expanded", "true")
    notify(error.message)
  }

  function clock(value) {
    const total = Math.max(0, Math.floor(value));
    return [Math.floor(total / 3600), Math.floor(total / 60) % 60, total % 60]
      .map((part) => String(part).padStart(2, "0")).join(":");
  }

  function safeRecordingUrl(value) {
    try {
      const url = new URL(value);
      if (["https:", "http:"].includes(url.protocol)) return url;
    } catch { /* A blank or incomplete URL has no link. */ }
    return null;
  }

  function recordingLink(at) {
    const url = safeRecordingUrl($("source-url").value);
    if (!url) return null;
    if (/(^|\.)(youtube\.com|youtu\.be)$/.test(url.hostname)) url.searchParams.set("t", `${Math.floor(at)}s`);
    return url.href;
  }

  function updateWatch() {
    const at = selected ? words[selected.start].start : 0
    const href = recordingLink(at)
    const link = $("watch")
    link.hidden = !href
    if (!href) return
    link.href = href
    link.textContent = at && href !== recordingLink(0) ? `Play from ${clock(at)} ↗` : "Watch recording ↗"
  }

  function renderTranscript() {
    const fragment = document.createDocumentFragment();
    elements = [];
    let paragraph, rowStart = -100, rowLength = 0;
    words.forEach((word, index) => {
      if (!paragraph || (word.start - rowStart >= 18 && rowLength > 90) || rowLength > 450) {
        const row = document.createElement("div");
        row.className = "row";
        const stamp = document.createElement("a");
        stamp.className = "stamp";
        stamp.textContent = clock(word.start);
        stamp.contentEditable = "false";
        const href = recordingLink(word.start);
        if (href) { stamp.href = href; stamp.target = "_blank"; stamp.rel = "noopener noreferrer"; stamp.title = "Open recording at this time"; }
        paragraph = document.createElement("div");
        paragraph.className = "words";
        row.append(stamp, paragraph);
        fragment.append(row);
        rowStart = word.start;
        rowLength = 0;
      }
      const span = document.createElement("span");
      span.className = "word";
      span.dataset.index = index;
      span.textContent = word.text + " ";
      paragraph.append(span);
      elements.push(span);
      rowLength += word.text.length + 1;
    });
    $("transcript").replaceChildren(fragment);
  }

  function renderSpeakers() {
    $("quick-speaker").replaceChildren(new Option("Choose a speaker", ""),
      ...state.names.map((name, index) => new Option(name, String(index))))
    $("speakers").replaceChildren(...state.names.map((name, index) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "desk-speaker"
      button.style.setProperty("--speaker-color", colors[index % colors.length])
      button.setAttribute("aria-label", name)
      const label = document.createElement("span")
      label.textContent = name
      button.append(label)
      if (index < 9) {
        const key = document.createElement("kbd")
        key.textContent = index + 1
        key.setAttribute("aria-hidden", "true")
        button.setAttribute("aria-keyshortcuts", String(index + 1))
        button.append(key)
      }
      button.dataset.speaker = index
      button.addEventListener("click", () => assign(index))
      return button
    }))
    updateSelection()
  }

  function renderNames() {
    $("name-fields").replaceChildren(...state.names.map((name, index) => {
      const label = document.createElement("label")
      label.className = "form-label"
      label.textContent = "Speaker " + (index + 1)
      const input = document.createElement("input")
      input.className = "form-input"
      input.value = name
      input.maxLength = 150
      input.addEventListener("change", () => {
        state.names[index] = input.value.trim() || name
        input.value = state.names[index]
        renderSpeakers()
        updateLabels()
        persist()
      })
      label.append(input)
      return label
    }))
  }

  function updateLabels() {
    for (const element of elements) {
      element.classList.remove("labeled");
      element.removeAttribute("title");
      element.style.removeProperty("--color");
      element.style.removeProperty("--tint");
    }
    let labeled = 0;
    for (const annotation of state.annotations) {
      labeled += annotation.end - annotation.start;
      for (let index = annotation.start; index < annotation.end; index++) {
        const element = elements[index];
        element.classList.add("labeled");
        element.style.setProperty("--color", colors[annotation.speaker % colors.length]);
        element.style.setProperty("--tint", colors[annotation.speaker % colors.length] + "20");
        element.title = state.names[annotation.speaker];
      }
    }
    const pct = Math.round(labeled / words.length * 100);

    $("progress").textContent = pct + "%"
    $("progress-bar").value = labeled / words.length * 100
    $("progress-detail").textContent = `${labeled.toLocaleString()} / ${words.length.toLocaleString()} words`
    $("review-summary").textContent = `${labeled.toLocaleString()} of ${words.length.toLocaleString()} words have a speaker. You can save a partially labeled forum.`
    $("label-count").textContent = state.annotations.length > 25 ? "(last 25 of " + state.annotations.length + ")" : "(" + state.annotations.length + ")"
    $("label-list").replaceChildren(...state.annotations.slice(-25).reverse().map(annotation => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "desk-button"
      button.textContent = clock(words[annotation.start].start) + " · " + state.names[annotation.speaker]
      button.title = words.slice(annotation.start, Math.min(annotation.start + 12, annotation.end)).map(word => word.text).join(" ")
      button.addEventListener("click", () => selectPassage(annotation.start, annotation.end))
      return button
    }))
    $("undo").disabled = undoStack.length === 0
    $("redo").disabled = redoStack.length === 0
    $("review-open").disabled = !labeled
  }

  function updateSelection() {
    if (markedSelection) {
      for (let index = markedSelection.start; index < markedSelection.end; index++) elements[index]?.classList.remove("pending");
    }
    markedSelection = selected && { ...selected };
    updateWatch()
    const active = Boolean(selected);
    const speaker = selectedSpeaker();
    $("clear").disabled = !active;
    $("quick-speaker").disabled = !active
    $("quick-speaker").value = speaker === null ? "" : String(speaker)
    $("selection-status").textContent = active ? `${selected.end - selected.start} words · ${clock(words[selected.start].start)}–${clock(words[selected.end - 1].end)}\n${speaker === null ? "Choose one speaker for this passage." : "Assigned to " + state.names[speaker]}` : "Highlight a passage in the transcript.";
    if (active) {
      for (let index = selected.start; index < selected.end; index++) elements[index].classList.add("pending");
    }
    for (const button of $("speakers").children) {
      button.disabled = !active;
      button.setAttribute("aria-pressed", String(active && Number(button.dataset.speaker) === speaker));
    }
  }

  function selectedSpeaker() {
    if (!selected) return null;
    const annotation = state.annotations.find((range) => range.start <= selected.start && range.end >= selected.end);
    return annotation?.speaker ?? null;
  }

  function captureSelection() {
    if (drag) return;
    const selection = getSelection();
    if (!selection.rangeCount || selection.isCollapsed) return;
    const range = selection.getRangeAt(0);
    if (!$("transcript").contains(range.startContainer) || !$("transcript").contains(range.endContainer)) return;
    const covered = [];
    elements.forEach((element, index) => {
      if (!range.intersectsNode(element)) return;
      const probe = document.createRange();
      probe.selectNodeContents(element);
      if (range.compareBoundaryPoints(Range.END_TO_START, probe) >= 0 || range.compareBoundaryPoints(Range.START_TO_END, probe) <= 0) return;
      covered.push(index);
    });
    if (!covered.length) return;
    selected = { start: covered[0], end: covered[covered.length - 1] + 1 };
    updateSelection();
  }

  function wordAtPoint(x, y) {
    let node;
    if (document.caretPositionFromPoint) node = document.caretPositionFromPoint(x, y)?.offsetNode;
    else node = document.caretRangeFromPoint(x, y)?.startContainer;
    const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
    const word = element?.closest(".word");
    if (word && $("transcript").contains(word)) return Number(word.dataset.index);
    return null;
  }

  function updateDragRange() {
    if (!drag) return;
    const box = $("transcript").getBoundingClientRect();
    const top = Math.max(box.top + 8, 8);
    const bottom = Math.min(box.bottom - 8, innerHeight - 8);
    const x = Math.max(box.left + 1, Math.min(drag.x, box.right - 1));
    const y = Math.max(top, Math.min(drag.y, bottom));
    const index = wordAtPoint(x, y);
    if (index !== null) drag.focus = index;
    const start = Math.min(drag.anchor, drag.focus);
    const end = Math.max(drag.anchor, drag.focus) + 1;
    const range = document.createRange();
    range.setStart(elements[start].firstChild, 0);
    range.setEnd(elements[end - 1].firstChild, elements[end - 1].textContent.length);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function scrollDrag(time) {
    if (!drag) return;
    const box = $("transcript").getBoundingClientRect();
    const top = Math.max(box.top, 0), bottom = Math.min(box.bottom, innerHeight);
    let direction = 0;
    if (drag.y < top + 32) direction = -Math.min(1, (top + 32 - drag.y) / 32);
    else if (drag.y > bottom - 32) direction = Math.min(1, (drag.y - bottom + 32) / 32);
    const elapsed = Math.min(time - drag.lastTime, 32) / 1000;
    drag.lastTime = time;
    if (direction) {
      $("transcript").scrollTop += direction * dragScrollPixelsPerSecond * elapsed;
      updateDragRange();
    }
    drag.frame = requestAnimationFrame(scrollDrag);
  }

  function finishDrag(event) {
    if (!drag || (event && event.pointerId !== drag.pointerId)) return;
    const finished = drag;
    cancelAnimationFrame(finished.frame);
    drag = null;
    if ($("transcript").hasPointerCapture(finished.pointerId)) $("transcript").releasePointerCapture(finished.pointerId);
    selected = { start: Math.min(finished.anchor, finished.focus), end: Math.max(finished.anchor, finished.focus) + 1 };
    getSelection().removeAllRanges();
    updateSelection();
  }

  $("transcript").addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "mouse" || event.button !== 0) return;
    const word = event.target.closest(".word");
    if (!word) return;
    // Own the drag so the browser cannot accelerate native selection scrolling.
    event.preventDefault();
    $("transcript").focus({ preventScroll: true });
    selected = null;
    updateSelection();
    const index = Number(word.dataset.index);
    drag = { anchor: index, focus: index, pointerId: event.pointerId,
      x: event.clientX, y: event.clientY, lastTime: performance.now() };
    $("transcript").setPointerCapture(event.pointerId);
    updateDragRange();
    drag.frame = requestAnimationFrame(scrollDrag);
  });
  $("transcript").addEventListener("pointermove", (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    event.preventDefault();
    drag.x = event.clientX;
    drag.y = event.clientY;
    updateDragRange();
  });
  $("transcript").addEventListener("pointerup", finishDrag);
  $("transcript").addEventListener("pointercancel", finishDrag);

  window.addEventListener("blur", () => finishDrag(), { signal })

  function assign(speaker) {
    if (!selected) return;
    undoStack.push(structuredClone(state.annotations));
    if (undoStack.length > 60) undoStack.shift();
    redoStack = [];
    const { start, end } = selected;
    const ranges = [];
    for (const annotation of state.annotations) {
      if (annotation.end <= start || annotation.start >= end) ranges.push(annotation);
      else {
        if (annotation.start < start) ranges.push({ ...annotation, end: start });
        if (annotation.end > end) ranges.push({ ...annotation, start: end });
      }
    }
    if (speaker !== null) ranges.push({ start, end, speaker });
    ranges.sort((a, b) => a.start - b.start);
    state.annotations = [];
    for (const annotation of ranges) {
      const last = state.annotations.at(-1);
      if (last && last.end === annotation.start && last.speaker === annotation.speaker) last.end = annotation.end;
      else state.annotations.push({ ...annotation });
    }
    getSelection().removeAllRanges();
    updateLabels(); updateSelection(); persist();
  }

  function history(from, to) {
    if (!from.length) return;
    to.push(structuredClone(state.annotations));
    state.annotations = from.pop();
    selected = null;
    getSelection().removeAllRanges();
    updateSelection(); updateLabels(); persist();
  }

  function download(filename, content, type) {
    const url = URL.createObjectURL(new Blob([content], { type }));
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  $("transcript").addEventListener("mouseup", captureSelection);
  $("transcript").addEventListener("touchend", () => setTimeout(captureSelection, 100));
  $("transcript").addEventListener("keyup", captureSelection);
  document.addEventListener("selectionchange", () => {
    if (drag || selectionFrame !== null) return;
    selectionFrame = requestAnimationFrame(() => {
      selectionFrame = null;
      const selection = getSelection();
      if (selection.anchorNode && $("transcript").contains(selection.anchorNode) && !selection.isCollapsed) captureSelection();
    });
  }, { signal });
  document.addEventListener("keydown", (event) => {
    if (!state || $("review-dialog").open || event.target.closest("input,textarea,select,summary") || event.ctrlKey || event.metaKey || event.altKey) return;
    if (selected && /^[1-9]$/.test(event.key) && Number(event.key) <= state.names.length) { event.preventDefault(); assign(Number(event.key) - 1); }
    if (event.key === "Escape") { selected = null; getSelection().removeAllRanges(); updateSelection(); }
  }, { signal });
  $("quick-speaker").addEventListener("change", event => {
    if (event.target.value !== "") assign(Number(event.target.value))
  })
  $("clear").addEventListener("click", () => assign(null));
  $("undo").addEventListener("click", () => history(undoStack, redoStack));
  $("redo").addEventListener("click", () => history(redoStack, undoStack));

  function selectPassage(start, end) {
    selected = { start, end }
    getSelection().removeAllRanges()
    updateSelection()
    const wordTop = elements[start].getBoundingClientRect().top
    transcript.scrollTop += wordTop - transcript.getBoundingClientRect().top - transcript.clientHeight / 3
  }

  $("next").addEventListener("click", () => {
    let start = 0;
    for (const annotation of state.annotations) {
      if (annotation.start > start) break;
      start = annotation.end;
    }
    if (start === words.length) { notify("Every word has a speaker label."); return; }
    const nextLabel = state.annotations.find((annotation) => annotation.start > start);
    selectPassage(start, Math.min(start + 45, nextLabel?.start ?? words.length, words.length))
  });

  $("add-speaker").addEventListener("click", () => {
    const name = $("new-speaker").value.trim()
    if (!name || state.names.includes(name)) return
    state.names.push(name)
    $("new-speaker").value = ""
    renderNames()
    renderSpeakers()
    persist()
  })
  $("source-url").addEventListener("change", () => {
    if (!current) return
    selected = null
    renderTranscript()
    updateLabels()
    updateSelection()
    persist()
  })
  $("forum-import").addEventListener("change", () => { if (current) persist() })
  $("forum-title").addEventListener("change", () => {
    $("reading-title").textContent = $("forum-title").value
    if (current) persist()
  })
  $("save").addEventListener("click", () => {
    download(current.filename.replace(/\.(srt|vtt)$/i, "") + "-speakers.json", JSON.stringify(project()), "application/json")
  })
  async function openFile(input, isProject) {
    const file = input.files[0]
    if (!file) return
    const ticket = ++generation
    try {
      if (file.size > 2_000_000) throw new Error("Choose a file smaller than 2 MB.")
      const raw = await file.text()
      if (isProject) {
        const data = JSON.parse(raw)
        if (typeof data.captions !== "string") throw new Error("This project has no captions.")
        await activate(ticket, data.captions, data.filename || file.name, data)
      } else {
        await activate(ticket, raw, file.name)
      }
    } catch (error) { if (ticket === generation) report(error) }
    finally { input.value = "" }
  }
  $("caption-file").addEventListener("change", event => openFile(event.target, false))
  $("project-file").addEventListener("change", event => openFile(event.target, true))
  $("manage-files").setAttribute("aria-expanded", String(!$("desk-files").hidden))
  $("manage-files").addEventListener("click", () => {
    $("desk-files").hidden = !$("desk-files").hidden
    $("manage-files").setAttribute("aria-expanded", String(!$("desk-files").hidden))
    if (!$("desk-files").hidden) $("caption-file").focus()
  })
  $("recording-switch")?.addEventListener("change", event => {
    if (event.target.value) {
      savePosition()
      window.location.assign(event.target.value)
    }
  })
  $("export").addEventListener("click", () => {
    const lines = [$("forum-title").value, $("source-url").value, "Caption SHA-256 " + current.hash,
      "Times and wording come from the captions.", ""]
    function append(start, end, name) {
      lines.push(`[${clock(words[start].start)}–${clock(words[end - 1].end)}] ${name}`,
        words.slice(start, end).map(word => word.text).join(" "), "")
    }
    let cursor = 0
    for (const label of state.annotations) {
      if (cursor < label.start) append(cursor, label.start, "Unlabeled")
      append(label.start, label.end, state.names[label.speaker])
      cursor = label.end
    }
    if (cursor < words.length) append(cursor, words.length, "Unlabeled")
    download(current.filename.replace(/\.(srt|vtt)$/i, "") + "-labeled.txt", lines.join("\n"), "text/plain")
  })
  const review = $("review-dialog")
  const form = $("forum-import")
  $("review-open").addEventListener("click", () => {
    $("recording-details").open = Boolean($("recording-details").querySelector(":invalid"))
    review.showModal()
  })
  $("review-close").addEventListener("click", () => review.close())
  form.addEventListener("submit", async event => {
    event.preventDefault()
    const data = project()
    if (!safeRecordingUrl(data.sourceUrl)) {
      $("recording-details").open = true
      $("source-url").setCustomValidity("Enter an HTTP or HTTPS recording URL.")
      $("source-url").reportValidity()
      return
    }
    const file = new File([JSON.stringify(data)], "forum-speakers.json", { type: "application/json" })
    const body = new FormData(form)
    body.set("forum[file]", file)
    $("save-forum").disabled = true
    $("review-error").hidden = true
    try {
      const response = await fetch(form.action, { method: "POST", body, signal,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content } })
      if (!response.headers.get("Content-Type")?.includes("application/json")) throw new Error("Your session may have expired. Download a backup and sign in again.")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Could not save this forum. Your draft is still open.")
      savePosition()
      if (result.saved) {
        try { localStorage.removeItem(current.key) } catch { /* The server has saved the reviewed version. */ }
      }
      window.location.assign(result.location)
    } catch (error) {
      if (!signal.aborted) {
        $("review-error").textContent = error.message
        $("review-error").hidden = false
        $("save-forum").disabled = false
      }
    }
  })
  $("source-url").addEventListener("input", () => $("source-url").setCustomValidity(""))
  if (root.dataset.project) {
    const initial = generation
    fetch(root.dataset.project, { signal }).then(async response => {
      if (!response.ok) throw new Error("Could not open the saved speaker project.")
      const data = await response.json()
      for (const [field, id] of [["organizer", "forum_publisher"], ["forumDate", "forum_published_on"],
                                  ["electionOn", "forum_election_on"], ["coverageNotes", "forum_coverage_notes"]]) {
        data[field] = $(id).defaultValue
      }
      if (initial === generation) await activate(initial, data.captions, data.filename || defaultTitle, data, true)
    }).catch(error => { if (initial === generation) report(error) })
  } else if (root.dataset.recording) {
    const initial = generation
    fetch(root.dataset.recording, { signal }).then(async response => {
      if (!response.ok || !response.headers.get("Content-Type")?.includes("text/vtt")) throw new Error("Open a local caption file to continue.")
      const raw = await response.text()
      if (initial === generation) await activate(initial, raw, defaultTitle + ".vtt")
    }).catch(error => { if (initial === generation) report(error) })
  }
  return () => { savePosition(); finishDrag(); cancelAnimationFrame(selectionFrame) }
}
