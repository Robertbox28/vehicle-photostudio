{
  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vehicle-photostudio';
  const $ = (id) => document.getElementById(id);
  const app = $('app'), grid = $('grid'), empty = $('empty'), detail = $('detail'), body = document.querySelector('.body');

  const state = { kind: 'player', items: [], canDelete: false, inStudio: false, filter: 'all', q: '', cat: '', sel: null, img: 0 };

  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
  const post = (name, data = {}) =>
    fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) })
      .then((r) => r.json()).catch(() => null);

  // ---- Lokale Bilder (local:datei.png) nachladen -------------------------
  const cache = new Map();      // datei -> dataUri | false
  const waiting = new Map();    // reqId -> [datei, callbacks]
  let reqSeq = 0;
  function resolveSrc(src, cb) {
    if (!src) return cb(null);
    if (!src.startsWith('local:')) return cb(src);
    const file = src.slice(6);
    if (cache.has(file)) return cb(cache.get(file) || null);
    for (const [, w] of waiting) if (w[0] === file) { w[1].push(cb); return; }
    const reqId = ++reqSeq;
    waiting.set(reqId, [file, [cb]]);
    post('image', { reqId, file });
  }
  function fillImg(holder, src, alt) {
    holder.innerHTML = '<div class="spin"></div>';
    resolveSrc(src, (real) => {
      if (!holder.isConnected) return;
      if (!real) { holder.innerHTML = '<div class="noimg"><span class="cam"></span>Bild fehlt</div>'; return; }
      const img = new Image();
      img.alt = alt || '';
      img.onerror = () => { holder.innerHTML = '<div class="noimg"><span class="cam"></span>Bild nicht erreichbar</div>'; };
      img.src = real;
      holder.replaceChildren(img);
    });
  }

  // ---- Liste ---------------------------------------------------------------
  const titleOf = (it) => [it.brand, it.name].filter(Boolean).join(' ') || it.model;
  const fmtPrice = (n) => (n ? '$' + Number(n).toLocaleString('de-CH') : null);
  const fmtDate = (it) => {
    const d = it.ts ? new Date(it.ts * 1000) : it.updated ? new Date(typeof it.updated === 'number' ? it.updated * 1000 : it.updated) : null;
    return d && !isNaN(d) ? d.toLocaleDateString('de-CH', { day: '2-digit', month: '2-digit', year: 'numeric' }) : null;
  };

  function visible() {
    const q = state.q.trim().toLowerCase();
    return state.items.filter((it) => {
      const n = arr(it.images).length;
      if (state.filter === 'with' && !n) return false;
      if (state.filter === 'without' && n) return false;
      if (state.cat && it.category !== state.cat) return false;
      if (!q) return true;
      return [it.name, it.brand, it.model, it.plate, it.category].some((v) => String(v || '').toLowerCase().includes(q));
    });
  }

  function renderSummary() {
    const total = state.items.length;
    const withPics = state.items.filter((it) => arr(it.images).length).length;
    const photos = state.items.reduce((s, it) => s + arr(it.images).length, 0);
    $('summary').textContent = state.kind === 'catalog'
      ? `${total} Fahrzeuge · ${withPics} mit Foto · ${total - withPics} ohne · ${photos} Bilder`
      : `${total} Fahrzeuge · ${photos} Fotos`;
  }

  function renderGrid() {
    const list = visible();
    empty.hidden = list.length > 0;
    grid.innerHTML = list.map((it) => {
      const imgs = arr(it.images);
      const sub = state.kind === 'player'
        ? `<span><i class="plate">${esc(it.plate)}</i> · ${esc(it.model)}</span>`
        : `<span>${esc(it.model)}${it.category ? ' · ' + esc(it.category) : ''}${it.custom ? ' · eigen' : ''}</span>`;
      const badge = imgs.length ? `<span class="badge">${imgs.length} ${imgs.length === 1 ? 'Foto' : 'Fotos'}</span>` : '<span class="badge miss">kein Foto</span>';
      return `<button type="button" class="card${state.sel === it.id ? ' sel' : ''}" data-id="${esc(it.id)}">
        <div class="thumb" data-src="${esc(imgs[0] ? imgs[0].src : '')}">${imgs.length ? '' : '<div class="noimg"><span class="cam"></span>Noch kein Foto</div>'}${badge}</div>
        <div class="meta"><b>${esc(titleOf(it))}</b>${sub}</div>
      </button>`;
    }).join('');
    // Bilder erst laden, wenn die Karte sichtbar wird
    grid.querySelectorAll('.thumb[data-src]').forEach((t) => { if (t.dataset.src) io.observe(t); });
  }

  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      io.unobserve(e.target);
      const badge = e.target.querySelector('.badge');
      const holder = document.createElement('div');
      holder.style.cssText = 'width:100%;height:100%;display:grid;place-items:center';
      e.target.replaceChildren(holder);
      if (badge) e.target.appendChild(badge);
      fillImg(holder, e.target.dataset.src);
    }
  }, { root: document.querySelector('.grid-wrap'), rootMargin: '200px' });

  // ---- Detail --------------------------------------------------------------
  function current() { return state.items.find((it) => it.id === state.sel) || null; }

  function renderDetail() {
    const it = current();
    detail.hidden = !it;
    body.classList.toggle('split', !!it);
    $('confirm').hidden = true;
    if (!it) return;

    const imgs = arr(it.images);
    if (state.img >= imgs.length) state.img = 0;
    const im = imgs[state.img];

    $('dName').textContent = titleOf(it);
    const frame = document.querySelector('.frame');
    const big = $('big');
    $('bigEmpty').hidden = !!im;
    big.hidden = !im;
    $('bigLabel').textContent = im ? [im.variant, im.label].filter(Boolean).join(' · ') : '';
    if (im) {
      big.removeAttribute('src');
      resolveSrc(im.src, (real) => { if (current() === it && imgs[state.img] === im) big.src = real || ''; });
    }
    frame.title = im && im.url ? im.url : '';

    $('thumbs').innerHTML = imgs.map((x, i) =>
      `<button type="button" class="${i === state.img ? 'on' : ''}" data-i="${i}"><div class="t" data-src="${esc(x.src)}"></div><small>${esc([x.variant, x.label].filter(Boolean).join(' · '))}</small></button>`
    ).join('');
    $('thumbs').querySelectorAll('.t').forEach((t) => fillImg(t, t.dataset.src));

    const facts = state.kind === 'player'
      ? [['Kennzeichen', it.plate], ['Modell', it.model], ['Fotos', imgs.length || 'keine'], ['Zuletzt', fmtDate(im || it)]]
      : [['Modell', it.model], ['Kategorie', it.category], ['Preis', fmtPrice(it.price)], ['Bilder', imgs.length || 'keine'], ['Aktualisiert', fmtDate(it)]];
    $('dFacts').innerHTML = facts.filter((f) => f[1] !== null && f[1] !== undefined && f[1] !== '')
      .map((f) => `<dt>${esc(f[0])}</dt><dd>${esc(f[1])}</dd>`).join('');

    $('copy').hidden = !(im && im.url);
    $('del').hidden = !(im && state.canDelete);
    $('shoot').hidden = !(state.kind === 'catalog' && !state.inStudio);
  }

  // ---- Aktionen ------------------------------------------------------------
  let toastTimer;
  function toast(msg, kind) {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast ' + (kind || '');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 2200);
  }

  function copyText(text) {
    const done = () => toast('Link kopiert', 'ok');
    const fallback = () => {
      const ta = $('clip');
      ta.value = text; ta.select();
      try { document.execCommand('copy') ? done() : toast('Kopieren nicht möglich', 'err'); } catch (_) { toast('Kopieren nicht möglich', 'err'); }
    };
    try { navigator.clipboard.writeText(text).then(done, fallback); } catch (_) { fallback(); }
  }

  function close() {
    app.hidden = true;
    state.sel = null;
    post('close');
  }

  grid.addEventListener('click', (e) => {
    const card = e.target.closest('.card');
    if (!card) return;
    state.sel = card.dataset.id === state.sel ? null : card.dataset.id;
    state.img = 0;
    grid.querySelectorAll('.card').forEach((c) => c.classList.toggle('sel', c.dataset.id === state.sel));
    renderDetail();
  });

  $('thumbs').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-i]');
    if (!b) return;
    state.img = Number(b.dataset.i);
    renderDetail();
  });

  $('copy').addEventListener('click', () => {
    const it = current(); const im = it && arr(it.images)[state.img];
    if (im && im.url) copyText(im.url);
  });

  $('shoot').addEventListener('click', () => {
    const it = current();
    if (it) { app.hidden = true; post('photograph', { model: it.model }); }
  });

  $('del').addEventListener('click', () => { $('confirm').hidden = false; });
  $('delNo').addEventListener('click', () => { $('confirm').hidden = true; });
  $('delYes').addEventListener('click', async () => {
    const it = current(); const im = it && arr(it.images)[state.img];
    if (!im) return;
    $('delYes').disabled = true;
    const res = await post('delete', { kind: state.kind, id: it.id, key: im.key });
    $('delYes').disabled = false;
    if (res && res.ok) {
      it.images = arr(it.images).filter((x) => x !== im);
      state.img = 0;
      toast('Foto gelöscht', 'ok');
      renderSummary(); renderGrid(); renderDetail();
    } else {
      toast('Löschen hat nicht geklappt', 'err');
      $('confirm').hidden = true;
    }
  });

  $('search').addEventListener('input', (e) => { state.q = e.target.value; renderGrid(); });
  $('category').addEventListener('change', (e) => { state.cat = e.target.value; renderGrid(); });
  $('filter').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-f]');
    if (!b) return;
    state.filter = b.dataset.f;
    $('filter').querySelectorAll('button').forEach((x) => x.classList.toggle('on', x === b));
    renderGrid();
  });
  $('close').addEventListener('click', close);
  document.addEventListener('keydown', (e) => {
    if (app.hidden) return;
    if (e.key === 'Escape' || (e.key === 'Tab' && document.activeElement !== $('search'))) { e.preventDefault(); close(); }
    const it = current();
    if (it && (e.key === 'ArrowRight' || e.key === 'ArrowLeft') && document.activeElement !== $('search')) {
      const n = arr(it.images).length;
      if (n > 1) { state.img = (state.img + (e.key === 'ArrowRight' ? 1 : n - 1)) % n; renderDetail(); }
    }
  });

  // ---- Menü an den festen Orten ----------------------------------------------
  const menu = $('menu');
  let menuLoc = null;
  const icon = (id) => (id === 'gallery' || id === 'catalog')
    ? '<span class="grid4"><i></i><i></i><i></i><i></i></span>'
    : '<span class="cam"></span>';
  function openMenu(d) {
    menuLoc = d.loc;
    $('menuTitle').textContent = d.title || 'Fotostudio';
    const items = arr(d.items);
    let html = '', sep = false;
    for (const it of items) {
      if (it.admin && !sep) { html += '<p class="menu-sep">Admin</p>'; sep = true; }
      html += `<button type="button" class="menu-item${it.admin ? ' admin' : ''}" data-id="${esc(it.id)}">
        <span class="ico">${icon(it.id)}</span><b>${esc(it.label)}</b><small>${esc(it.desc || '')}</small></button>`;
    }
    $('menuItems').innerHTML = html;
    menu.hidden = false;
    const first = menu.querySelector('.menu-item');
    if (first) setTimeout(() => first.focus(), 30);
  }
  function closeMenu(notify) {
    menu.hidden = true;
    if (notify) post('menuClose');
  }
  $('menuItems').addEventListener('click', (e) => {
    const b = e.target.closest('.menu-item');
    if (!b) return;
    closeMenu(false);
    post('menuSelect', { id: b.dataset.id, loc: menuLoc });
  });
  document.addEventListener('keydown', (e) => {
    if (menu.hidden) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); closeMenu(true); }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      const list = [...menu.querySelectorAll('.menu-item')];
      const i = list.indexOf(document.activeElement);
      const n = list[(i + (e.key === 'ArrowDown' ? 1 : list.length - 1)) % list.length];
      if (n) { e.preventDefault(); n.focus(); }
    }
  });

  // ---- Nachrichten vom Spiel -----------------------------------------------
  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') {
      state.kind = d.kind === 'catalog' ? 'catalog' : 'player';
      state.items = arr(d.items).map((it) => ({ ...it, id: String(it.id), images: arr(it.images) }));
      state.canDelete = !!d.canDelete;
      state.inStudio = !!d.inStudio;
      state.sel = null; state.img = 0; state.q = ''; state.cat = ''; state.filter = 'all';
      $('search').value = '';
      $('filter').querySelectorAll('button').forEach((x) => x.classList.toggle('on', x.dataset.f === 'all'));
      $('title').textContent = state.kind === 'catalog' ? 'Fahrzeugkatalog' : 'Meine Fahrzeugfotos';
      $('del').textContent = state.kind === 'catalog' ? 'Bild löschen' : 'Foto löschen';

      const cats = [...new Set(state.items.map((it) => it.category).filter(Boolean))].sort();
      $('category').hidden = state.kind !== 'catalog' || cats.length < 2;
      $('category').innerHTML = '<option value="">Alle Kategorien</option>' + cats.map((c) => `<option value="${esc(c)}">${esc(c)}</option>`).join('');

      app.hidden = false;
      renderSummary(); renderGrid(); renderDetail();
      setTimeout(() => $('search').focus(), 50);
    } else if (d.action === 'menu') {
      openMenu(d);
    } else if (d.action === 'close') {
      app.hidden = true;
      state.sel = null;
    } else if (d.action === 'image') {
      const w = waiting.get(d.reqId);
      if (!w) return;
      waiting.delete(d.reqId);
      cache.set(w[0], d.src || false);
      w[1].forEach((cb) => cb(d.src || null));
    }
  });
}
