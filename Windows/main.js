'use strict';
const { app, BrowserWindow, ipcMain, nativeTheme, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn, execFile } = require('child_process');

// ---------------------------------------------------------------- настройки
const FAST = process.env.EMBERS_FAST_QUEUE === '1';       // для проверки: минуты → секунды
const MINUTE = FAST ? 1000 : 60000;
const GAP_MS = 5000;                                       // пауза между играми очереди
const MARGIN_MS = FAST ? 2000 : 45000;                     // запас сверх времени квеста
const DEFAULT_GOAL_MS = 15 * 60000;
const DB_URL = 'https://discord.com/api/v9/applications/detectable';
const DAY_MS = 24 * 3600 * 1000;

if (!app.requestSingleInstanceLock()) { app.quit(); }
nativeTheme.themeSource = 'dark';

// ---------------------------------------------------------------- файлы
const dataDir = () => app.getPath('userData');
const fakeRoot = () => path.join(dataDir(), 'fake');
const resource = (name) => app.isPackaged
  ? path.join(process.resourcesPath, name)
  : path.join(__dirname, 'resources', name);

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJson(file, data) {
  try { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data)); } catch { /* не критично */ }
}

// ---------------------------------------------------------------- состояние
let win = null;
let games = [];
const byId = new Map();
const sessions = new Map();          // gameId -> { gameId, startedAt, goalMs, child }
let queue = [];                      // [{ uid, gameId, minutes }]
let queueRunning = false;
let currentUid = null;
let nextStartAt = null;
let doneCount = 0;
let refreshing = false;
let lastError = null;
let queueToken = 0;                  // увеличиваем, чтобы отменить текущий цикл очереди
let settings = { lang: 'en', langChosen: false };

function sortGames(list) {
  const isLetter = (s) => /^\p{L}/u.test(s);
  return list.slice().sort((a, b) => {
    const la = isLetter(a.n), lb = isLetter(b.n);
    if (la !== lb) return la ? -1 : 1;
    return a.n.localeCompare(b.n, 'en', { sensitivity: 'base' });
  });
}

function setGames(list) {
  games = sortGames(list);
  byId.clear();
  for (const g of games) byId.set(g.i, g);
}

function loadGames() {
  const cache = path.join(dataDir(), 'games.json');
  let list = readJson(cache, null);
  if (!Array.isArray(list) || !list.some((g) => g.v)) list = readJson(resource('games.json'), []);
  setGames(list);
  let stale = true;
  try { stale = Date.now() - fs.statSync(cache).mtimeMs > DAY_MS; } catch { /* кэша нет */ }
  if (stale) refreshDb();
}

async function refreshDb() {
  if (refreshing) return;
  refreshing = true; lastError = null; emit();
  try {
    const res = await fetch(DB_URL);
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const raw = await res.json();
    const out = [];
    for (const g of raw) {
      const exes = (g.executables || [])
        .filter((e) => (e.os === 'darwin' || e.os === 'win32') && !e.is_launcher && e.name)
        .map((e) => ({ n: e.name.replace(/^>+/, ''), o: e.os }));
      if (!exes.length) continue;
      const o = { i: g.id, n: g.name, c: g.icon_hash || null, e: exes };
      if (g.cover_image_hash) o.v = g.cover_image_hash;
      out.push(o);
    }
    if (out.length) {
      writeJson(path.join(dataDir(), 'games.json'), out);
      setGames(out);
      win?.webContents.send('games-updated');
    }
  } catch (e) {
    lastError = 'refresh: ' + e.message;
  } finally {
    refreshing = false; emit();
  }
}

// ---------------------------------------------------------------- запуск «игр»
function helperPath() {
  if (process.env.EMBERS_HELPER) return process.env.EMBERS_HELPER;        // для проверки на Mac
  return resource(process.platform === 'win32' ? 'fakegame.exe' : 'fakegame');
}

function pickExe(game) {
  const win32 = game.e.find((x) => x.o === 'win32');
  const darwin = game.e.find((x) => x.o === 'darwin');
  if (process.platform === 'win32' || process.env.EMBERS_PICK_WIN === '1') return win32 || null;
  return darwin || win32 || null;
}

function makeBinary(game, exe) {
  const parts = exe.n.split(/[\\/]/).filter((p) => p && p !== '.' && p !== '..');
  if (!parts.length) throw new Error('bad executable name');
  const dir = path.join(fakeRoot(), game.i);
  fs.rmSync(dir, { recursive: true, force: true });
  const target = path.join(dir, ...parts);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(helperPath(), target);
  fs.chmodSync(target, 0o755);
  return target;
}

function startGame(id, goalMs = DEFAULT_GOAL_MS) {
  const game = byId.get(id);
  if (!game || sessions.has(id)) return false;
  const exe = pickExe(game);
  if (!exe) { lastError = { key: 'noWindows', name: game.n }; emit(); return false; }
  try {
    const target = makeBinary(game, exe);
    const child = spawn(target, [], { stdio: 'ignore', windowsHide: true });
    const s = { gameId: id, startedAt: Date.now(), goalMs, child };
    child.on('error', (e) => { sessions.delete(id); lastError = { key: 'startFailed', name: game.n, detail: e.message }; emit(); });
    child.on('exit', () => { if (sessions.get(id) === s) sessions.delete(id); emit(); });
    sessions.set(id, s);
    emit();
    return true;
  } catch (e) {
    lastError = { key: 'startFailed', name: game.n, detail: e.message };
    emit();
    return false;
  }
}

function stopGame(id) {
  const s = sessions.get(id);
  if (!s) return;
  try { s.child.kill(); } catch { /* уже закрыт */ }
}

function stopAllGames() {
  for (const id of [...sessions.keys()]) stopGame(id);
}

// Пустышки, оставшиеся после аварийного выхода.
function killStrays() {
  const root = fakeRoot();
  if (process.platform === 'win32') {
    const ps = `Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like '${root.replace(/'/g, "''")}*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`;
    execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', ps], { windowsHide: true }, () => {});
  } else {
    execFile('pkill', ['-f', root + '/'], () => {});
  }
}

// ---------------------------------------------------------------- очередь
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let uidSeq = Date.now();

async function runQueue(token) {
  while (token === queueToken && queue.length) {
    const item = queue[0];
    currentUid = item.uid;
    const goal = item.minutes * MINUTE + MARGIN_MS;
    emit();
    if (!startGame(item.gameId, goal)) break;
    const end = Date.now() + goal;
    while (token === queueToken && Date.now() < end && sessions.has(item.gameId)) await sleep(500);
    if (token !== queueToken) return;                       // очередь остановили
    stopGame(item.gameId);
    queue = queue.filter((q) => q.uid !== item.uid);
    
    doneCount++;
    currentUid = null;
    if (!queue.length) break;
    nextStartAt = Date.now() + GAP_MS;
    emit();
    await sleep(GAP_MS);
    nextStartAt = null;
  }
  if (token === queueToken) {
    queueRunning = false; currentUid = null; nextStartAt = null; emit();
  }
}

function startQueue() {
  if (queueRunning || !queue.length) return;
  stopAllGames();
  queueRunning = true; doneCount = 0;
  const token = ++queueToken;
  runQueue(token);
  emit();
}

function stopQueue() {
  queueToken++;
  const cur = queue.find((q) => q.uid === currentUid);
  if (cur) stopGame(cur.gameId);
  queueRunning = false; currentUid = null; nextStartAt = null;
  emit();
}

// ---------------------------------------------------------------- команды из окна
const commands = {
  start: (id) => startGame(id),
  stop: (id) => stopGame(id),
  enqueue: (id) => {
    if (!byId.has(id) || queue.some((q) => q.gameId === id)) return;
    queue.push({ uid: ++uidSeq, gameId: id, minutes: 15 });
    emit();
  },
  dequeue: (uid) => {
    if (uid === currentUid) { const q = queue.find((x) => x.uid === uid); if (q) stopGame(q.gameId); return; }
    queue = queue.filter((q) => q.uid !== uid); emit();
  },
  move: ({ uid, delta }) => {
    const i = queue.findIndex((q) => q.uid === uid), j = i + delta;
    if (i < 0 || j < 0 || j >= queue.length || queue[i].uid === currentUid || queue[j].uid === currentUid) return;
    [queue[i], queue[j]] = [queue[j], queue[i]]; emit();
  },
  setMinutes: ({ uid, minutes }) => {
    const q = queue.find((x) => x.uid === uid);
    if (q && uid !== currentUid) { q.minutes = minutes; emit(); }
  },
  clearQueue: () => { stopQueue(); queue = []; doneCount = 0; emit(); },
  startQueue: () => startQueue(),
  stopQueue: () => stopQueue(),
  skip: () => { const q = queue.find((x) => x.uid === currentUid); if (q) stopGame(q.gameId); },
  refreshDb: () => refreshDb(),
  setLang: (lang) => { settings.lang = lang === 'ru' ? 'ru' : 'en'; settings.langChosen = true; writeJson(path.join(dataDir(), 'settings.json'), settings); emit(); },
  dismissError: () => { lastError = null; emit(); },
  openLink: (url) => { if (/^https:\/\//.test(url)) shell.openExternal(url); },
};

function snapshot() {
  return {
    sessions: [...sessions.values()].map((s) => ({ id: s.gameId, startedAt: s.startedAt, goalMs: s.goalMs })),
    queue, queueRunning, currentUid, nextStartAt, doneCount, refreshing,
    error: lastError, lang: settings.lang, langChosen: !!settings.langChosen, minuteMs: MINUTE, gameCount: games.length,
  };
}

let emitTimer = null;
function emit() {
  if (emitTimer) return;
  emitTimer = setTimeout(() => {
    emitTimer = null;
    if (win && !win.isDestroyed()) win.webContents.send('state', snapshot());
  }, 16);
}

ipcMain.handle('cmd', (_e, name, arg) => (commands[name] ? commands[name](arg) : undefined));
ipcMain.handle('state', () => snapshot());
ipcMain.handle('games', () => games);

// ---------------------------------------------------------------- окно
function createWindow() {
  win = new BrowserWindow({
    width: 1060, height: 800, minWidth: 760, minHeight: 600,
    backgroundColor: '#12100E',
    title: 'Embers',
    icon: path.join(__dirname, 'resources', 'icon.png'),
    autoHideMenuBar: true,
    titleBarStyle: 'hidden',
    titleBarOverlay: { color: '#12100E', symbolColor: '#F5EFE8', height: 44 },
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
  });
  win.setMenu(null);
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.on('closed', () => { win = null; });
}

app.whenReady().then(() => {
  if (process.platform === 'win32') app.setAppUserModelId('app.embers.questrunner');
  settings = { ...settings, ...readJson(path.join(dataDir(), 'settings.json'), {}) };
  // Очередь хранится только в памяти. Файл от прошлых версий удаляем, чтобы ничего не оставалось.
  try { fs.rmSync(path.join(dataDir(), 'queue.json'), { force: true }); } catch { /* нет файла */ }
  killStrays();
  loadGames();
  createWindow();
});

app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
app.on('window-all-closed', () => app.quit());
app.on('before-quit', () => { queueToken++; stopAllGames(); });
