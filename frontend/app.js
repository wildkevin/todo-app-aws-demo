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

  const text = document.createElement("span");
  text.className = "row__text";
  text.textContent = todo.text;

  const del = document.createElement("button");
  del.className = "row__delete";
  del.setAttribute("aria-label", "delete");
  del.textContent = "✕";

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

// -- bootstrap --
fetchTodos().catch((err) => {
  console.error(err);
  addError.textContent = "Could not load tasks: " + err.message;
  addError.hidden = false;
});
