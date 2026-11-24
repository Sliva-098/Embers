'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const featuredNames = [
    'EVE Online', 'Honkai: Star Rail', 'Genshin Impact', 'Zenless Zone Zero', 'Wuthering Waves',
    'Marvel Rivals', 'ARKNIGHTS: ENDFIELD', 'Dune: Awakening', 'Delta Force', 'THE FINALS',
    'Once Human', 'Throne and Liberty', 'NARAKA: BLADEPOINT', 'Warframe', 'Destiny 2',
    'VALORANT', 'Fortnite', 'Apex Legends', 'Rocket League', 'Palworld',
  ];
  const DURATIONS = [5, 10, 15, 20, 30, 45, 60, 90, 120];
  const PAGE = 60;                         // сколько плиток дорисовывать за раз

  const ico = {
    play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
    stop: '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
    skip: '<svg viewBox="0 0 24 24"><path d="M6 5v14l9-7zM17 5h2v14h-2z"/></svg>',
    plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
    check: '<svg viewBox="0 0 24 24"><path d="m5 12.500 4.500 4.500L19 7.500"/></svg>',
    up: '<svg viewBox="0 0 24 24"><path d="m6 15 6-6 6 6"/></svg>',
    down: '<svg viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></svg>',
    x: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    pad: '<svg viewBox="0 0 24 24"><path d="M6 8h12a3 3 0 0 1 3 3v4a3 3 0 0 1-5.200 2L14 15h-4l-1.800 2A3 3 0 0 1 3 15v-4a3 3 0 0 1 3-3Z"/><path d="M8 11v3M6.500 12.500h3M16 11.500h.01M18 13.500h.01"/></svg>',
  };

  let S = null;                  // состояние из главного процесса
  let games = [];
  let byId = new Map();
  let featured = [];
  let query = '';
  let shown = 0;
  let results = [];
  let lang = 'en';
  const tr = () => window.I18N[lang];
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const clock = (ms) => { const s = Math.max(0, Math.floor(ms / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
  const num = (n) => n.toLocaleString(lang === 'ru' ? 'ru-RU' : 'en-US');

  // ------------------------------------------------------------ обложки и плитки
  function coverHtml(g, extra = '') {
    const letter = esc((g.n[0] || '?').toUpperCase());
    if (g.v) return `<div class="cover ${extra}"><div class="letter">${letter}</div><img loading="lazy" alt="" src="https://cdn.discordapp.com/app-icons/${g.i}/${g.v}.png?size=512" onerror="this.remove()"></div>`;
    if (g.c) return `<div class="cover icon ${extra}"><div class="letter">${letter}</div><img loading="lazy" alt="" src="https://cdn.discordapp.com/app-icons/${g.i}/${g.c}.png?size=128" onerror="this.remove()"></div>`;
    return `<div class="cover ${extra}"><div class="letter">${letter}</div></div>`;
  }
  const isRunning = (id) => !!S && S.sessions.some((s) => s.id === id);
  const isQueued = (id) => !!S && S.queue.some((q) => q.gameId === id);
  const exeOf = (g) => (g.e.find((x) => x.o === 'win32') || g.e[0]);
  const hasWin = (g) => g.e.some((x) => x.o === 'win32');

  // Плитка собирается так, чтобы оверлеи лежали внутри .cover
  function makeTile(g) {
    const T = tr();
    const el = document.createElement('div');
    el.className = 'tile';
    el.dataset.id = g.i;
    el.tabIndex = 0;
    el.setAttribute('role', 'button');
    el.innerHTML = coverHtml(g) + `<h3>${esc(g.n)}</h3><p class="sub">${esc(hasWin(g) ? T.runsOnPc : T.macOnly)}</p>`;
    const cover = el.querySelector('.cover');
    cover.insertAdjacentHTML('beforeend',
      `<div class="shade"></div><span class="play">${ico.play}</span>
       <button class="plus" data-act="queue">${ico.plus}</button>
       <span class="badge on"><i class="dot" style="background:var(--orange-ink)"></i><span class="elapsed"></span></span>
       <span class="badge q">${esc(T.inQueue)}</span>`);
    paintTile(el);
    return el;
  }

  function paintTile(el) {
    const id = el.dataset.id, g = byId.get(id), T = tr();
    const running = isRunning(id), queued = isQueued(id);
    el.classList.toggle('running', running);
    el.classList.toggle('queued', queued);
    el.title = running ? T.stop(g.n) : T.start(g.n);
    const plus = el.querySelector('.plus');
    if (plus) { plus.innerHTML = queued ? ico.check : ico.plus; plus.title = queued ? T.alreadyQueued : T.addQueue; }
    el.querySelector('.sub').textContent = running ? T.clickToStop : (hasWin(g) ? T.runsOnPc : T.macOnly);
  }

  function paintAllTiles() { document.querySelectorAll('.tile').forEach(paintTile); }

  document.addEventListener('click', (e) => {
    const tile = e.target.closest('.tile');
    if (!tile) return;
    const id = tile.dataset.id;
    if (e.target.closest('[data-act="queue"]')) { e.stopPropagation(); if (!isQueued(id)) window.embers.cmd('enqueue', id); return; }
    window.embers.cmd(isRunning(id) ? 'stop' : 'start', id);
  });
  document.addEventListener('keydown', (e) => {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.classList?.contains('tile')) { e.preventDefault(); e.target.click(); }
  });

  // ------------------------------------------------------------ панель «сейчас играет»
  function renderNow() {
    const T = tr(), box = $('now');
    const sessions = S.sessions;
    const cur = S.currentUid ? S.queue.find((q) => q.uid === S.currentUid) : null;
    const curSession = cur ? sessions.find((s) => s.id === cur.gameId) : null;
    const main = curSession || sessions[sessions.length - 1];

    if (!main && S.nextStartAt && S.queue.length) {
      const g = byId.get(S.queue[0].gameId);
      box.innerHTML = `<div class="now">${g ? `<div style="width:104px;flex:none;opacity:.6">${coverHtml(g)}</div>` : ''}
        <div class="info play"><div class="state"><span class="dot"></span><span class="js-next"></span></div>
          <h1>${esc(g ? g.n : '')}</h1>
          <div class="exe">${esc(T.doneInQueue(S.doneCount))}</div></div>
        <div class="actions"><button class="btn" id="bStopQ">${ico.stop}${esc(T.stopQueue)}</button></div></div>`;
      $('bStopQ').onclick = () => window.embers.cmd('stopQueue');
      return;
    }
    if (!main) {
      box.innerHTML = `<div class="now"><div class="idle-icon">${ico.pad}</div>
        <div class="info"><h1 class="idle">${esc(T.nothingRunning)}</h1><p class="hint">${esc(T.idleHint)}</p></div></div>`;
      return;
    }
    const g = byId.get(main.id);
    const fromQueue = !!(cur && curSession);
    const goalMin = fromQueue ? cur.minutes : 15;
    const goalMs = goalMin * S.minuteMs;
    const others = sessions.filter((s) => s.id !== main.id);
    box.innerHTML = `<div class="now">${coverHtml(g)}
      <div class="info play">
        <div class="state"><span class="dot"></span><span class="js-state"></span></div>
        <h1>${esc(g.n)}</h1>
        <div class="exe">${esc(exeOf(g).n)}</div>
        <div class="clock"><b class="js-elapsed">0:00</b><span>${esc(T.of(clock(goalMs)))}</span></div>
      </div>
      <div class="actions">${fromQueue
        ? `<button class="btn" id="bSkip">${ico.skip}${esc(T.skip)}</button><button class="btn" id="bStopQ">${ico.stop}${esc(T.stopQueue)}</button>`
        : `<button class="btn" id="bStop">${ico.stop}${esc(T.stopBtn)}</button>`}</div></div>
      <div class="track"><i class="js-bar" style="width:0"></i></div>
      ${others.length ? `<div class="also">${esc(T.alsoRunning)} ${others.map((o) => `<button class="chip" data-stop="${o.id}">${esc(byId.get(o.id)?.n || o.id)}${ico.x}</button>`).join('')}<span style="margin-left:auto">${esc(T.countsAll)}</span></div>` : ''}`;
    box.dataset.main = main.id; box.dataset.start = main.startedAt; box.dataset.goal = goalMs;
    box.dataset.fromQueue = fromQueue ? '1' : '';
    box.dataset.left = fromQueue ? Math.max(0, S.queue.length - 1) : '';
    box.dataset.minutes = goalMin;
    $('bSkip') && ($('bSkip').onclick = () => window.embers.cmd('skip'));
    $('bStopQ') && ($('bStopQ').onclick = () => window.embers.cmd('stopQueue'));
    $('bStop') && ($('bStop').onclick = () => window.embers.cmd('stop', main.id));
    box.querySelectorAll('[data-stop]').forEach((b) => { b.onclick = () => window.embers.cmd('stop', b.dataset.stop); });
    tick();
  }

  // ------------------------------------------------------------ очередь
  function renderQueue() {
    const T = tr(), box = $('queueBox');
    if (!S.queue.length) { box.innerHTML = ''; return; }
    const total = S.queue.reduce((a, q) => a + q.minutes, 0);
    const rows = S.queue.map((q, i) => {
      const g = byId.get(q.gameId); if (!g) return '';
      const cur = q.uid === S.currentUid;
      const opts = DURATIONS.map((m) => `<option value="${m}"${m === q.minutes ? ' selected' : ''}>${esc(T.min(m))}</option>`).join('');
      return `<div class="qrow${cur ? ' current' : ''}">${coverHtml(g)}
        <div class="name"><b>${esc(g.n)}</b><span>${esc(cur ? T.runningNow : T.waiting)}</span></div>
        <select class="mins" data-uid="${q.uid}" title="${esc(T.minutesHelp)}"${cur ? ' disabled' : ''}>${opts}</select>
        <button class="ibtn" data-move="-1" data-uid="${q.uid}" title="${esc(T.up)}"${i === 0 || cur ? ' disabled' : ''}>${ico.up}</button>
        <button class="ibtn" data-move="1" data-uid="${q.uid}" title="${esc(T.down)}"${i === S.queue.length - 1 || cur ? ' disabled' : ''}>${ico.down}</button>
        <button class="ibtn" data-del="${q.uid}" title="${esc(cur ? T.skip : T.remove)}">${ico.x}</button></div>`;
    }).join('');
    box.innerHTML = `<div class="row-head"><h2>${esc(T.queue)}<small>${esc(T.queueSummary(S.queue.length, total))}</small></h2>
      <div>${S.queueRunning ? '' : `<button class="link" id="qClear">${esc(T.clear)}</button><button class="btn primary" id="qStart">${ico.play}${esc(T.startQueue)}</button>`}</div></div>
      <div class="qlist">${rows}</div>`;
    $('qClear') && ($('qClear').onclick = () => window.embers.cmd('clearQueue'));
    $('qStart') && ($('qStart').onclick = () => window.embers.cmd('startQueue'));
    box.querySelectorAll('select.mins').forEach((s) => { s.onchange = () => window.embers.cmd('setMinutes', { uid: +s.dataset.uid, minutes: +s.value }); });
    box.querySelectorAll('[data-move]').forEach((b) => { b.onclick = () => window.embers.cmd('move', { uid: +b.dataset.uid, delta: +b.dataset.move }); });
    box.querySelectorAll('[data-del]').forEach((b) => { b.onclick = () => window.embers.cmd('dequeue', +b.dataset.del); });
  }

  // ------------------------------------------------------------ библиотека
  function renderFeatured() {
    const T = tr(), box = $('featured');
    if (query || !featured.length) { box.innerHTML = ''; return; }
    box.innerHTML = `<div class="row-head"><h2>${esc(T.often)}<small>${esc(T.oftenNote)}</small></h2></div><div class="rail"></div>`;
    const rail = box.querySelector('.rail');
    featured.forEach((g) => rail.appendChild(makeTile(g)));
  }

  function renderLibrary() {
    const T = tr(), box = $('library');
    const q = query.trim().toLowerCase();
    if (!q) results = games;
    else {
      const hits = games.filter((g) => g.n.toLowerCase().includes(q));
      results = hits.filter((g) => g.n.toLowerCase().startsWith(q)).concat(hits.filter((g) => !g.n.toLowerCase().startsWith(q)));
    }
    shown = 0;
    box.innerHTML = `<div class="row-head"><h2>${esc(q ? T.results : T.allGames)}<small>${esc(q ? T.forQuery(num(results.length), query.trim()) : T.gamesFrom(num(games.length)))}</small></h2></div>
      ${results.length ? '<div class="grid" id="grid"></div><div id="sentinel"></div>' : `<p class="empty">${esc(T.noResults)}</p>`}`;
    more();
  }

  function more() {
    const grid = $('grid');
    if (!grid || shown >= results.length) return;
    const frag = document.createDocumentFragment();
    for (const g of results.slice(shown, shown + PAGE)) frag.appendChild(makeTile(g));
    shown += PAGE;
    grid.appendChild(frag);
  }
  $('scroll').addEventListener('scroll', () => {
    const el = $('scroll');
    if (el.scrollTop + el.clientHeight > el.scrollHeight - 700) more();
  });

  // ------------------------------------------------------------ шапка и тексты
  function renderChrome() {
    const T = tr();
    $('langLabel').textContent = lang === 'en' ? 'EN' : 'RU';
    $('lang').title = T.switchLang;
    $('refresh').title = T.refresh;
    $('refresh').classList.toggle('spin', !!S.refreshing);
    $('search').placeholder = T.searchPlaceholder;
    $('clearSearch').title = T.clearSearch;
    document.documentElement.lang = lang;
  }

  function showError() {
    const T = tr(), box = $('toast'), e = S.error;
    if (!e) { box.hidden = true; return; }
    let msg = '';
    if (typeof e === 'string') msg = T.errRefresh;
    else if (e.key === 'noWindows') msg = T.errNoWindows(e.name);
    else if (e.key === 'startFailed') msg = T.errStart(e.name, e.detail || '');
    box.textContent = msg; box.hidden = false;
    clearTimeout(showError.t);
    showError.t = setTimeout(() => window.embers.cmd('dismissError'), 6000);
  }

  // ------------------------------------------------------------ таймеры раз в секунду
  function tick() {
    if (!S) return;
    const T = tr(), now = Date.now();
    const box = $('now');
    if (box.dataset.main && box.querySelector('.js-elapsed')) {
      const el = now - Number(box.dataset.start), goal = Number(box.dataset.goal);
      box.querySelector('.js-elapsed').textContent = clock(el);
      box.querySelector('.js-bar').style.width = Math.min(100, (el / goal) * 100) + '%';
      const done = el >= goal;
      const fromQueue = !!box.dataset.fromQueue, minutes = Number(box.dataset.minutes), left = Number(box.dataset.left || 0);
      box.querySelector('.js-state').textContent = done
        ? (fromQueue ? T.timesUp : T.minutesDone(minutes))
        : (fromQueue ? (left > 0 ? T.queueMore(left) : T.queueLast) : T.discordSees);
    }
    const nx = box.querySelector('.js-next');
    if (nx && S.nextStartAt) nx.textContent = T.nextIn(Math.max(0, Math.ceil((S.nextStartAt - now) / 1000)));
    S.sessions.forEach((s) => {
      document.querySelectorAll(`.tile[data-id="${s.id}"] .elapsed`).forEach((n) => { n.textContent = T.playing(clock(now - s.startedAt)); });
    });
  }
  setInterval(tick, 1000);

  // ------------------------------------------------------------ состояние
  function apply(state) {
    $('picker').hidden = !!state.langChosen;   // окно выбора языка — только пока язык не выбран
    const langChanged = state.lang !== lang;
    S = state; lang = state.lang;
    renderChrome(); renderNow(); renderQueue(); paintAllTiles(); showError(); tick();
    if (langChanged) { renderFeatured(); renderLibrary(); }
  }

  async function loadGames() {
    games = await window.embers.games();
    byId = new Map(games.map((g) => [g.i, g]));
    const lower = new Map(games.map((g) => [g.n.toLowerCase(), g]));
    featured = featuredNames.map((n) => lower.get(n.toLowerCase())).filter(Boolean);
    if (S) { renderNow(); renderQueue(); renderFeatured(); renderLibrary(); }
  }

  $('pickEn').onclick = () => window.embers.cmd('setLang', 'en');
  $('pickRu').onclick = () => window.embers.cmd('setLang', 'ru');
  document.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !$('picker').hidden) window.embers.cmd('setLang', 'en'); });
  $('lang').onclick = () => window.embers.cmd('setLang', lang === 'en' ? 'ru' : 'en');
  $('refresh').onclick = () => window.embers.cmd('refreshDb');
  $('search').addEventListener('input', (e) => {
    query = e.target.value; $('clearSearch').hidden = !query;
    renderFeatured(); renderLibrary();
  });
  $('clearSearch').onclick = () => { $('search').value = ''; query = ''; $('clearSearch').hidden = true; renderFeatured(); renderLibrary(); $('search').focus(); };
  document.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'f') { e.preventDefault(); $('search').focus(); } });
  $('kbd').textContent = navigator.platform.toLowerCase().includes('mac') ? '⌘F' : 'Ctrl F';

  window.embers.onState(apply);
  window.embers.onGames(() => loadGames());
  (async () => {
    S = await window.embers.state();
    lang = S.lang;
    await loadGames();
    apply(S);
    renderFeatured(); renderLibrary();
  })();
})();
