const LIST_ENDPOINT = () => `${window.API_BASE_URL}/todos`;
const ITEM_ENDPOINT = (id) => `${window.API_BASE_URL}/todos/${encodeURIComponent(id)}`;

let todos = [];
let filter = "all"; // "all" | "active" | "completed"
const pendingDeletes = new Map(); // id -> { timeoutId }

const listEl = document.getElementById("list");
const countEl = document.getElementById("count");
const emptyEl = document.getElementById("empty");
const clearBtn = document.getElementById("clear-completed");
const addForm = document.getElementById("add-form");
const addInput = document.getElementById("add-input");
const addError = document.getElementById("add-error");
const filtersEl = document.getElementById("filters");
const toastEl = document.getElementById("toast");
const toastMessageEl = document.getElementById("toast-message");
const toastUndoBtn = document.getElementById("toast-undo");

async function fetchTodos() {
  const res = await fetch(LIST_ENDPOINT());
  if (!res.ok) throw new Error("failed to load todos");
  todos = await res.json();
  render();
}

function visibleTodos() {
  return todos.filter((t) => {
    if (pendingDeletes.has(t.id)) return false;
    if (filter === "active") return !t.completed;
    if (filter === "completed") return t.completed;
    return true;
  });
}

function emptyMessage() {
  if (filter === "active") return "Nothing active.";
  if (filter === "completed") return "Nothing completed yet.";
  return "Nothing here yet.";
}

function buildRow(todo) {
  const li = document.createElement("li");
  li.className = "row" + (todo.completed ? " row--done" : "");
  li.dataset.id = todo.id;

  const check = document.createElement("button");
  check.className = "row__check";
  check.setAttribute("aria-label", "toggle complete");
  check.innerHTML = `<svg viewBox="0 0 20 20"><path d="M4 10 L8 14 L16 5" /></svg>`;
  check.addEventListener("click", () => toggleTodo(todo));

  const text = document.createElement("span");
  text.className = "row__text";
  text.textContent = todo.text;

  const del = document.createElement("button");
  del.className = "row__delete";
  del.setAttribute("aria-label", "delete");
  del.textContent = "✕";
  del.addEventListener("click", () => deleteTodo(todo));

  li.appendChild(check);
  li.appendChild(text);
  li.appendChild(del);
  return li;
}

function render() {
  const visible = visibleTodos();
  listEl.innerHTML = "";
  visible.forEach((todo) => listEl.appendChild(buildRow(todo)));

  const openCount = todos.filter((t) => !t.completed && !pendingDeletes.has(t.id)).length;
  countEl.textContent = `${openCount} open`;

  emptyEl.hidden = visible.length !== 0;
  emptyEl.textContent = emptyMessage();

  const hasCompleted = todos.some((t) => t.completed && !pendingDeletes.has(t.id));
  clearBtn.hidden = !hasCompleted;
}

async function createTodo(text) {
  const res = await fetch(LIST_ENDPOINT(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "failed to add task");
  todos.push(data);
  render();
}

addForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  addError.hidden = true;
  const text = addInput.value.trim();
  try {
    await createTodo(text);
    addInput.value = "";
  } catch (err) {
    addError.textContent = err.message;
    addError.hidden = false;
  }
});

async function toggleTodo(todo) {
  const previous = todo.completed;
  todo.completed = !previous;
  render();
  try {
    const res = await fetch(ITEM_ENDPOINT(todo.id), { method: "PATCH" });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "failed to update task");
    todo.completed = data.completed;
  } catch (err) {
    todo.completed = previous;
    console.error(err);
  }
  render();
}

let toastTimeoutId = null;

function showToast(message, onUndo) {
  toastMessageEl.textContent = message;
  toastEl.hidden = false;
  toastUndoBtn.onclick = onUndo;
}

function hideToast() {
  toastEl.hidden = true;
  toastUndoBtn.onclick = null;
}

function deleteTodo(todo) {
  const timeoutId = setTimeout(() => finalizeDelete(todo.id), 5000);
  pendingDeletes.set(todo.id, { timeoutId });
  render();
  showToast("Task deleted", () => undoDelete(todo.id));
}

function undoDelete(id) {
  const pending = pendingDeletes.get(id);
  if (!pending) return;
  clearTimeout(pending.timeoutId);
  pendingDeletes.delete(id);
  hideToast();
  render();
}

async function finalizeDelete(id) {
  pendingDeletes.delete(id);
  hideToast();
  try {
    const res = await fetch(ITEM_ENDPOINT(id), { method: "DELETE" });
    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.error || "failed to delete task");
    }
    todos = todos.filter((t) => t.id !== id);
  } catch (err) {
    console.error(err);
    await fetchTodos();
    return;
  }
  render();
}

// -- bootstrap --
fetchTodos().catch((err) => {
  console.error(err);
  addError.textContent = "Could not load tasks: " + err.message;
  addError.hidden = false;
});
