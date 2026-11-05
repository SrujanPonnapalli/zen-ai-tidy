// ==UserScript==
// @name           Zen AI Tidy
// @description    Arc-style "Tidy" for Zen: groups loose tabs into folders with on-device Apple Intelligence.
// ==/UserScript==

// Built against Zen 1.24b internals: gZenWorkspaces, gZenFolders.createFolder, zen-folder.addTabs.
const { Subprocess } = ChromeUtils.importESModule("resource://gre/modules/Subprocess.sys.mjs");
// Dev install (install.sh symlink) first, then Homebrew on Apple silicon and Intel.
const HELPER_PATHS = [
  PathUtils.join(PathUtils.profileDir, "chrome", "tidy-helper"),
  "/opt/homebrew/bin/tidy-helper",
  "/usr/local/bin/tidy-helper",
];
const INSTALL_HINT = "brew tap SrujanPonnapalli/zen-ai-tidy https://github.com/SrujanPonnapalli/zen-ai-tidy && brew install tidy-helper";
const findHelper = async () => {
  for (const p of HELPER_PATHS) if (await IOUtils.exists(p)) return p;
  return null;
};
const ICONS = "chrome://browser/skin/zen-icons/";

// Button text per state, and the matching workspace-menu label.
const STATES = {
  idle:  { label: "Tidy",          menu: "Tidy Tabs",  tip: "Group loose tabs into folders with on-device AI" },
  busy:  { label: "Tidying…",      menu: "Tidying…",   tip: "Sorting tabs with Apple Intelligence…" },
  undo:  { label: "Undo",          menu: "Undo Tidy",  tip: "Put the tabs back where they were" },
  empty: { label: "Nothing to tidy", menu: "Tidy Tabs", tip: "No loose tabs to group" },
  done:  { label: "Already tidy",  menu: "Tidy Tabs",  tip: "No groups found for these tabs" },
  error: { label: "Couldn't tidy", menu: "Tidy Tabs",  tip: "See zen-ai-tidy.log in your profile folder" },
  missing: { label: "Helper not installed", menu: "Tidy Tabs", tip: `Install it in Terminal: ${INSTALL_HINT}` },
};

let state = "idle";
let resetTimer = null;
let lastTidy = null; // { tabs, folders } from the most recent tidy in this window, for undo

function setState(next, { revertAfter } = {}) {
  state = next;
  clearTimeout(resetTimer);
  const s = STATES[next];
  for (const b of document.querySelectorAll(".zen-ai-tidy-button")) {
    b.setAttribute("tidy-state", next);
    b.setAttribute("label", s.label);
    b.setAttribute("tooltiptext", s.tip);
  }
  const item = document.querySelector(".zen-ai-tidy-menuitem");
  if (item) {
    item.setAttribute("tidy-state", next);
    item.setAttribute("label", s.menu);
    item.disabled = next === "busy";
  }
  if (revertAfter) resetTimer = setTimeout(() => setState("idle"), revertAfter);
}

const isLoose = t =>
  t.localName === "tab" && t.isConnected && !t.pinned && !t.group &&
  !t.hasAttribute("zen-essential") && !t.hasAttribute("zen-empty-tab") && !t.hasAttribute("zen-glance-tab");

// nsIURI.host throws for host-less URIs such as about:newtab.
const hostOf = t => { try { return t.linkedBrowser?.currentURI?.host || ""; } catch { return ""; } };

async function runHelper(helper, input) {
  const proc = await Subprocess.call({ command: helper, stderr: "pipe" });
  await proc.stdin.write(JSON.stringify(input));
  await proc.stdin.close();
  const readAll = async pipe => { let s = "", c; while ((c = await pipe.readString())) s += c; return s; };
  const [out, err] = await Promise.all([readAll(proc.stdout), readAll(proc.stderr)]);
  const { exitCode } = await proc.wait();
  if (exitCode !== 0) throw new Error(err.trim() || `tidy-helper exited ${exitCode}`);
  return JSON.parse(out).groups;
}

async function tidy() {
  const workspaceId = gZenWorkspaces.activeWorkspace;
  const tabs = gZenWorkspaces.tabboxChildrenWithoutEmpty.filter(isLoose);
  if (tabs.length < 2) return setState("empty", { revertAfter: 2500 });
  const folders = [...(gZenWorkspaces.pinnedTabsContainer?.querySelectorAll("zen-folder") ?? [])]
    .filter(f => !f.isLiveFolder);

  const helper = await findHelper();
  if (!helper) return setState("missing", { revertAfter: 6000 });

  setState("busy");
  try {
    const groups = await runHelper(helper, {
      tabs: tabs.map((t, id) => ({ id, title: t.label || "", host: hostOf(t) })),
      existing: folders.map(f => f.label),
    });
    const moved = [], created = [];
    for (const g of groups) {
      // Tabs may have been closed, pinned or grouped by the user while the model ran.
      const groupTabs = g.ids.map(id => tabs[id]).filter(t => t && isLoose(t));
      if (!groupTabs.length) continue;
      const folder = folders.find(f => f.isConnected && f.label.toLowerCase() === g.name.toLowerCase());
      if (folder) {
        groupTabs.forEach(t => gBrowser.pinTab(t)); // Zen folders only hold pinned tabs
        folder.addTabs(groupTabs);
      } else if (groupTabs.length >= 2) {
        created.push(gZenFolders.createFolder(groupTabs, { label: g.name, workspaceId }));
      } else continue;
      moved.push(...groupTabs);
    }
    lastTidy = moved.length ? { tabs: moved, folders: created } : null;
    lastTidy ? setState("undo") : setState("done", { revertAfter: 2500 });
  } catch (e) {
    console.error("[zen-ai-tidy]", e);
    // Last error goes to <profile>/zen-ai-tidy.log so it can be read without the Browser Console.
    IOUtils.writeUTF8(PathUtils.join(PathUtils.profileDir, "zen-ai-tidy.log"),
      `${new Date().toISOString()} ${e}\n${e?.stack ?? ""}\n`).catch(() => {});
    setState("error", { revertAfter: 4000 });
  }
}

async function untidy() {
  const { tabs, folders } = lastTidy;
  lastTidy = null;
  for (const t of tabs) {
    if (!t.isConnected) continue;
    if (t.group) gBrowser.ungroupTab(t);
    if (t.pinned) gBrowser.unpinTab(t);
  }
  // Remove folders we created once only Zen's placeholder tab is left in them.
  for (const f of folders) {
    if (f.isConnected && f.allItemsRecursive.every(t => t.hasAttribute("zen-empty-tab"))) await f.delete();
  }
  setState("idle");
}

function onCommand() {
  if (state === "busy") return;
  (lastTidy ? untidy() : tidy()).catch(e => { console.error("[zen-ai-tidy]", e); setState("idle"); });
}

const CSS = `
.zen-ai-tidy-button { list-style-image: url("${ICONS}paintbrush.svg"); }
.zen-ai-tidy-button[tidy-state="busy"] { list-style-image: url("${ICONS}sparkles.svg"); }
.zen-ai-tidy-button[tidy-state="undo"] { list-style-image: url("${ICONS}arrow-rotate-anticlockwise.svg"); }
/* While working or offering undo, stay visible even when the sidebar isn't hovered. */
.pinned-tabs-container-separator .zen-ai-tidy-button:is([tidy-state="busy"], [tidy-state="undo"]) {
  pointer-events: auto;
  background-image: none;
  & .toolbarbutton-icon, & .toolbarbutton-text { opacity: 0.7; }
}
@media not (prefers-reduced-motion: reduce) {
  .zen-ai-tidy-button[tidy-state="busy"] .toolbarbutton-icon {
    animation: zen-ai-tidy-pulse 1.1s ease-in-out infinite alternate;
  }
}
@keyframes zen-ai-tidy-pulse { from { opacity: 0.35; scale: 0.85; } to { opacity: 1; scale: 1.1; } }
`;

function addStyles() {
  const style = document.createElementNS("http://www.w3.org/1999/xhtml", "style");
  style.textContent = CSS;
  document.documentElement.append(style);
}

function addButtons() {
  for (const sep of document.querySelectorAll(".pinned-tabs-container-separator")) {
    if (sep.querySelector(".zen-ai-tidy-button")) continue;
    const btn = document.createXULElement("toolbarbutton");
    btn.className = "zen-ai-tidy-button";
    btn.addEventListener("command", onCommand);
    const close = sep.querySelector(".zen-workspace-close-unpinned-tabs-button");
    if (close) close.before(btn); else sep.append(btn);
  }
  setState(state);
}

function addMenuItem() {
  const popup = document.getElementById("zenWorkspaceMoreActions");
  if (!popup || popup.querySelector(".zen-ai-tidy-menuitem")) return;
  const item = document.createXULElement("menuitem");
  item.className = "zen-ai-tidy-menuitem";
  item.addEventListener("command", onCommand);
  popup.prepend(item, document.createXULElement("menuseparator"));
}

// Undo only makes sense right after a tidy; forget it once the user changes tabs.
gBrowser.tabContainer.addEventListener("TabSelect", () => {
  if (lastTidy && state === "undo") { lastTidy = null; setState("idle"); }
});
window.addEventListener("ZenWorkspacesUIUpdate", addButtons);
addStyles();
addMenuItem();
gZenWorkspaces.promiseInitialized.then(addButtons);
