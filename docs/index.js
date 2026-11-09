// docs/data.json を読んで、ガラスのタイルに描く
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (d) => { const [y, m, day] = d.split('-'); return `${y}年${+m}月${+day}日`; };
const short = (d) => { const [, m, day] = d.split('-'); return `${+m}/${+day}`; };
const day = (s) => new Date(s + 'T00:00:00');
const STATE = { done: '済', now: 'いま', todo: 'これから' };
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

let data = null;
// 中身は頻繁に書き換えるので、毎回サーバーに新しいか確かめる
fetch('data.json', { cache: 'no-cache' })
  .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
  .then((d) => { data = d; paint(); })
  .catch((e) => {
    $('main').insertAdjacentHTML('afterbegin', `<p class="tile in" style="grid-column:span 12" role="alert">data.json を読めませんでした（${esc(e.message)}）。GitHub Pages か手元のサーバーで開いてください。</p>`);
  });

// いま開いているページ（main の data-page）に合わせて描く
function paint() {
  if (!data) return;
  const page = $('main').dataset.page;
  if (page === 'art') {
    if (!data.art) throw new Error('data.json に art がない');
    renderArt(data.art); reveal();
  } else if (page === 'sound') {
    if (!data.sound) throw new Error('data.json に sound がない');
    renderSound(data.sound); reveal();
  } else if (page === 'decisions') {
    loadDecisions();
  } else if (page === 'history') {
    loadHistory();
  } else render(data);
}

// タイルを順に浮かせる
function reveal() {
  [...document.querySelectorAll('.tile')].forEach((t, i) => setTimeout(() => t.classList.add('in'), reduce ? 0 : 60 * i));
}

function render(d) {
  $('title').textContent = d.title;
  $('updated').dateTime = d.updated;
  $('updated').textContent = fmt(d.updated);
  $('goal').textContent = d.goal;
  $('pitch').textContent = d.pitch;

  // 次の節目: 最後に決めた日から節目の日までを環にする
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const due = day(d.next.due);
  const left = Math.max(0, Math.ceil((due - today) / 86400000));
  const start = day(d.decisions[d.decisions.length - 1].date);
  const total = Math.max(1, Math.round((due - start) / 86400000));
  const passed = Math.min(total, Math.max(0, Math.round((today - start) / 86400000)));
  $('next-label').textContent = d.next.label;
  $('next-due').dateTime = d.next.due;
  $('next-due').textContent = fmt(d.next.due);

  // 道のり
  const ni = Math.max(0, d.phases.findIndex((p) => p.state === 'now'));
  const track = $('track');
  track.style.setProperty('--n', d.phases.length);
  track.innerHTML = d.phases.map((p, i) =>
    `<li class="${p.state}"${p.state === 'now' ? ' aria-current="step"' : ''}><span class="node" aria-hidden="true"></span><span class="no num">${String(i + 1).padStart(2, '0')}</span><span class="nm">${esc(p.name)}</span><span class="nt">${esc(p.note)}</span></li>`).join('');

  // 作業: いま → これから → 済
  const order = { now: 0, todo: 1, done: 2 };
  const tasks = [...d.tasks].sort((a, b) => order[a.state] - order[b.state]);
  const done = tasks.filter((t) => t.state === 'done').length;
  $('tasks-count').textContent = `${done} / ${tasks.length}`;
  $('tasks').innerHTML = tasks.map((t) =>
    `<li class="${t.state}"><span class="mark" aria-hidden="true"></span><span><span class="sr">${STATE[t.state]}: </span>${esc(t.text)}</span></li>`).join('');

  // 決めたこと（新しい順）
  $('decisions').innerHTML = [...d.decisions].reverse().map((x) =>
    `<li><time datetime="${x.date}">${short(x.date)}</time>${esc(x.text)}</li>`).join('');

  // まだ決めていない
  $('questions').innerHTML = d.questions.map((q, i) =>
    `<li><span class="idx">${String(i + 1).padStart(2, '0')}</span><span>${esc(q)}</span></li>`).join('');

  // 計測: 一番長い時間を 78% の幅として比べる
  let barFills = [];
  if (d.climb) {
    $('climb-h').textContent = d.climb.label;
    const max = Math.max(...d.climb.rows.map((r) => r.sec));
    const min = Math.min(...d.climb.rows.map((r) => r.sec));
    $('bars').innerHTML = d.climb.rows.map((r) => {
      const w = (r.sec / max * 78).toFixed(1) + '%';
      return `<div class="bar${r.sec === min ? ' fast' : ''}" style="--w:${w}"><span class="who">${r.people}人</span><span class="rail"><span class="fill" data-w="${w}"></span><span class="val">${r.sec}<small>${esc(d.climb.unit)}</small></span></span></div>`;
    }).join('');
    $('climb-cap').textContent = d.climb.note;
    barFills = [...document.querySelectorAll('.bar .fill')];
  } else {
    $('climb-h').closest('.tile').hidden = true;
  }

  // 場所・お金・参考・はじまり
  $('places').innerHTML = d.places.map((p) => `<div><dt>${esc(p.name)}</dt><dd>${esc(p.note)}</dd></div>`).join('');
  $('costs').innerHTML = d.costs.map((c) =>
    `<tr><td>${esc(c.item)}</td><td class="amt">${esc(c.yen)}${/\d/.test(c.yen) ? '<small>円</small>' : ''}</td><td class="note">${esc(c.note)}</td></tr>`).join('');
  $('refs').innerHTML = d.refs.map((r) => `<div><dt>${esc(r.name)}</dt><dd>${esc(r.note)}</dd></div>`).join('');
  $('origin').textContent = d.origin;

  // 現れ方: タイルを順に浮かせ、図を伸ばし、数字を数え上げる
  reveal();
  requestAnimationFrame(() => requestAnimationFrame(() => {
    $('ring').style.strokeDashoffset = (326.7 * (1 - passed / total)).toFixed(1);
    track.style.setProperty('--progress', (ni / (d.phases.length - 1) * 100).toFixed(1) + '%');
    $('tasks-meter').style.width = (done / tasks.length * 100).toFixed(1) + '%';
    barFills.forEach((f) => { f.style.width = f.dataset.w; });
    countUp($('days'), left);
  }));
}

// アート: 決まり・素材・色・ゲームに入っているか・未定
function renderArt(a) {
  $('art-goal').textContent = a.concept;
  $('art-pitch').textContent = a.pitch;
  $('art-rules').innerHTML = a.rules.map((r, i) =>
    `<li><span class="idx">${String(i + 1).padStart(2, '0')}</span><span>${esc(r)}</span></li>`).join('');
  $('art-mats').innerHTML = a.materials.map((m) =>
    `<div><dt>${esc(m.name)}</dt><dd class="use">${esc(m.use)}</dd><dd>${esc(m.note)}</dd></div>`).join('');
  $('art-pal').innerHTML = a.palette.map((c) =>
    `<li><span class="chip" style="--c:${esc(c.hex)}" aria-hidden="true"></span><span class="cn">${esc(c.name)}</span><span class="hex num">${esc(c.hex)}</span></li>`).join('');
  $('art-scene').innerHTML = a.scene.map((s) =>
    `<li class="${s.state}"><span class="mark" aria-hidden="true"></span><span><span class="sr">${s.state === 'done' ? '入っている' : 'これから'}: </span><b>${esc(s.name)}</b><span class="sn">${esc(s.note)}</span></span></li>`).join('');
  $('art-open').innerHTML = a.open.map((o) => `<div><dt>${esc(o.name)}</dt><dd>${esc(o.note)}</dd></div>`).join('');
}

// 音: 考え方と、合成した音を聞く。音の一覧は sound/manifest.json（gen/publish.py が書く）
const player = new Audio();
let playingBtn = null;
player.addEventListener('ended', () => setPlaying(null));
player.addEventListener('pause', () => { if (player.ended || player.currentTime === 0) setPlaying(null); });
function setPlaying(btn) {
  if (playingBtn) { playingBtn.classList.remove('on'); playingBtn.setAttribute('aria-pressed', 'false'); }
  playingBtn = btn;
  if (btn) { btn.classList.add('on'); btn.setAttribute('aria-pressed', 'true'); }
}
// 音量のつまみ。dB で動かし、いちばん左は消音。決めた値はこのブラウザに覚えておく
function setupVolume() {
  const vol = $('snd-vol');
  if (!vol) return;
  try { const v = localStorage.getItem('lodge-snd-vol'); if (v !== null) vol.value = v; } catch (e) {}
  const apply = () => {
    const db = Number(vol.value);
    player.volume = db <= -60 ? 0 : 10 ** (db / 20);
    $('snd-vol-out').textContent = db <= -60 ? '消音' : `${db < 0 ? '−' : ''}${Math.abs(db)} dB`;
  };
  vol.addEventListener('input', () => { apply(); try { localStorage.setItem('lodge-snd-vol', vol.value); } catch (e) {} });
  apply();
}
function show(f) {
  const fig = $('snd-fig');
  if (!fig) return;
  fig.hidden = false;
  $('snd-img').src = `sound/png/${f.file.replace(/\.wav$/, '.png')}`;
  $('snd-img').alt = `${f.file} の波形とスペクトログラム`;
  $('snd-cap').textContent = `${f.file}　${f.dur} 秒　ピーク ${f.peak} dB　実効値 ${f.rms} dB${f.loop ? '　ループ' : ''}`;
}
function renderSound(s) {
  $('snd-goal').textContent = s.concept;
  $('snd-pitch').textContent = s.pitch;
  const plain = (xs) => xs.map((r, i) => `<li><span class="idx">${String(i + 1).padStart(2, '0')}</span><span>${esc(r)}</span></li>`).join('');
  $('snd-rules').innerHTML = plain(s.rules);
  $('snd-hear').innerHTML = plain(s.hear);
  $('snd-silent').innerHTML = plain(s.silent);
  $('snd-moment').innerHTML = plain(s.moment);
  $('snd-ask').innerHTML = s.ask.map((o) => `<div><dt>${esc(o.name)}</dt><dd>${esc(o.note)}</dd></div>`).join('');
  setupVolume();
  fetch('sound/manifest.json', { cache: 'no-cache' })
    .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then((files) => {
      $('snd-count').textContent = `${files.length} 本`;
      const byName = Object.fromEntries(files.map((f) => [f.file, f]));
      $('snd-groups').innerHTML = s.groups.map((g) => `<h3 class="snd-g">${esc(g.name)}</h3><div class="snd-items">` + g.items.map((it) => {
        const fs = files.filter((f) => f.file.startsWith(it.prefix));
        const btns = fs.map((f, i) => {
          const label = it.labels ? it.labels[i] : fs.length === 1 ? (f.loop ? 'ループ' : '再生') : (f.file.match(/(\d\d)\.wav$/) || [, String(i + 1)])[1];
          return `<button type="button" class="snd-btn${f.loop ? ' loop' : ''}" data-file="${esc(f.file)}" aria-pressed="false" title="${esc(f.file)}　${f.dur} 秒"><span class="tri" aria-hidden="true"></span>${esc(label)}</button>`;
        }).join('');
        const dur = fs.length ? (fs.length === 1 ? `${fs[0].dur} 秒` : `${fs.length} 種 · ${Math.min(...fs.map((f) => f.dur))}〜${Math.max(...fs.map((f) => f.dur))} 秒`) : 'まだない';
        return `<div class="snd-item"><div class="snd-head"><b>${esc(it.name)}</b><span class="num snd-dur">${esc(dur)}</span></div><p class="snd-note">${esc(it.note)}</p><div class="snd-btns">${btns}</div></div>`;
      }).join('') + '</div>').join('');
      $('snd-groups').addEventListener('click', (e) => {
        const b = e.target.closest('.snd-btn');
        if (!b) return;
        const f = byName[b.dataset.file];
        if (playingBtn === b && !player.paused) { player.pause(); player.currentTime = 0; setPlaying(null); return; }
        player.pause();
        player.src = `sound/wav/${f.file}`;
        player.loop = f.loop;
        player.currentTime = 0;
        player.play().catch(() => {});
        setPlaying(b);
        show(f);
      });
      const first = files.find((f) => f.file === 'music_speaker_loop.wav') || files[0];
      if (first) show(first);
    })
    .catch((e) => { $('snd-groups').innerHTML = `<p class="cap" role="alert">sound/manifest.json を読めませんでした（${esc(e.message)}）。</p>`; });
}

// 判断: ポリシーの案と、セッションごとの記録。量が多いので data.json とは別に読む
function loadDecisions() {
  fetch('decisions.json', { cache: 'no-cache' })
    .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then((d) => { renderDecisions(d); reveal(); openFromHash(); })
    .catch((e) => {
      $('main').insertAdjacentHTML('afterbegin', `<p class="tile in" style="grid-column:span 12" role="alert">decisions.json を読めませんでした（${esc(e.message)}）。</p>`);
    });
}
const QS = { report: 'Claude の報告にある引用', none: '本人の字句は記録にない' };
function quoteLine(x) {
  if (x.quote) return `<q>${esc(x.quote)}</q>${x.qs === 'report' ? `<span class="dec-src">${QS.report}</span>` : ''}`;
  return `<span class="dec-src">${QS.none}</span>`;
}
function renderDecisions(d) {
  const by = {};
  d.sessions.forEach((s) => s.decisions.forEach((x) => { by[x.id] = x; }));
  const link = (id) => `<a class="dec-ref num" href="#d-${esc(id)}">${esc(id)}</a>`;
  $('dec-updated').dateTime = d.updated;
  $('dec-updated').textContent = fmt(d.updated);
  $('dec-goal').textContent = d.hero.title;
  $('dec-pitch').textContent = d.hero.pitch;
  $('dec-count').textContent = `セッション ${d.about.sessions} 件、判断 ${d.about.decisions} 件、ポリシーの案 ${d.about.policies} 件`;
  const groups = [...new Set(d.policies.map((p) => p.group))];
  $('dec-policies').innerHTML = groups.map((g) => `<section class="tile dec-group"><h2>${esc(g)}</h2><ol class="dec-pol">` +
    d.policies.filter((p) => p.group === g).map((p) => {
      const quoted = p.evidence.filter((i) => by[i].quote).slice(0, 2);
      return `<li id="${esc(p.id)}"><h3>${esc(p.title)}</h3><p>${esc(p.rule)}</p>` +
        (p.why ? `<p class="dec-why">${esc(p.why)}</p>` : '') +
        (p.exception ? `<p class="dec-why">${esc(p.exception)}</p>` : '') +
        quoted.map((i) => `<p class="dec-q">${quoteLine(by[i])}</p>`).join('') +
        `<p class="dec-refs">根拠 ${p.evidence.map(link).join(' ')}</p></li>`;
    }).join('') + '</ol></section>').join('');
  $('dec-changed').innerHTML = d.changed.map((c) => `<li><b>${esc(c.topic)}</b><span>${esc(c.text)}</span><span class="dec-refs">根拠 ${c.evidence.map(link).join(' ')}</span></li>`).join('');
  $('dec-ses-count').textContent = `${d.sessions.length} 件`;
  $('dec-sessions').innerHTML = d.sessions.map((s) => `<details class="dec-ses" id="s-${s.n}"><summary><span class="num idx">${String(s.n).padStart(2, '0')}</span><span class="dec-ses-t">${esc(s.title)}</span><span class="dec-ses-m num">${esc(s.dates || '')} ・ 判断 ${s.decisions.length} 件</span></summary>` +
    `<h3>やったこと</h3><ul>${s.did.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>` +
    (s.outcome ? `<h3>どう終わったか</h3><p>${esc(s.outcome)}</p>` : '') +
    (s.decisions.length ? `<h3>判断</h3><ol class="dec-list">${s.decisions.map((x) => `<li id="d-${esc(x.id)}"><span class="dec-id num">${esc(x.id)}</span><span class="dec-tag">${esc(x.kind)}</span><span class="dec-tag">${esc(x.scope)}</span>${x.date ? `<time class="num" datetime="${esc(x.date)}">${short(x.date)}</time>` : ''}<p>${esc(x.decision)}</p><p class="dec-q">${quoteLine(x)}</p>${x.why ? `<p class="dec-why">理由: ${esc(x.why)}</p>` : ''}</li>`).join('')}</ol>` : '') +
    (s.open && s.open.length ? `<h3>記録の時点で残っていたこと</h3><ul>${s.open.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>` : '') +
    '</details>').join('');
  $('main').addEventListener('click', (e) => {
    const a = e.target.closest('a.dec-ref');
    if (!a) return;
    e.preventDefault();
    history.replaceState(null, '', a.getAttribute('href'));
    openFromHash();
  });
}
// #d-8-18 のような根拠へ飛ぶとき、閉じているセッションを開く
function openFromHash() {
  if (!location.hash.startsWith('#d-')) return;
  const el = document.getElementById(location.hash.slice(1));
  if (!el) return;
  const s = el.closest('details');
  if (s) s.open = true;
  el.scrollIntoView({ block: 'center' });
  el.classList.add('dec-hit');
  setTimeout(() => el.classList.remove('dec-hit'), 1600);
}

// 軌跡: 量が多いので、描く道具（history.js / history.css）も中身（history.json）も、開いたときに読む
function once(tag, attrs) {
  const key = attrs.src || attrs.href;
  const had = document.querySelector(`${tag}[${attrs.src ? 'src' : 'href'}^="${key.split('?')[0]}"]`);
  if (had) return had.dataset.ready === '0' ? new Promise((ok, ng) => { had.addEventListener('load', ok); had.addEventListener('error', ng); }) : Promise.resolve();
  return new Promise((ok, ng) => {
    const el = Object.assign(document.createElement(tag), attrs);
    el.dataset.ready = '0';
    el.addEventListener('load', () => { el.dataset.ready = '1'; ok(); });
    el.addEventListener('error', () => ng(new Error(`${key} を読めない`)));
    document.head.append(el);
  });
}
function loadHistory() {
  Promise.all([
    once('link', { rel: 'stylesheet', href: 'history.css?v=2' }),
    once('script', { src: 'history.js?v=2' }),
    fetch('history.json', { cache: 'no-cache' }).then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); }),
  ]).then(([, , h]) => { window.renderHistory(h); reveal(); })
    .catch((e) => {
      $('main').insertAdjacentHTML('afterbegin', `<p class="tile in" style="grid-column:span 12" role="alert">軌跡を読めませんでした（${esc(e.message)}）。</p>`);
    });
}

// ページの行き来: 読み込み直さず、相手のページの main だけ取ってきて差し替える
document.addEventListener('click', (e) => {
  const a = e.target.closest('.tabs a');
  if (!a || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  e.preventDefault();
  if (a.getAttribute('aria-current') !== 'page') go(a.href, true);
});
addEventListener('popstate', () => go(location.href, false));

async function go(url, push) {
  try {
    const r = await fetch(url);
    if (!r.ok) throw new Error(r.status);
    const doc = new DOMParser().parseFromString(await r.text(), 'text/html');
    const next = doc.getElementById('main');
    if (!next) throw new Error('main がない');
    $('main').replaceWith(document.adoptNode(next));
    document.title = doc.title;
    document.querySelector('meta[name=description]').content = doc.querySelector('meta[name=description]').content;
    document.querySelectorAll('.tabs a').forEach((l) => {
      if (l.dataset.page === next.dataset.page) l.setAttribute('aria-current', 'page'); else l.removeAttribute('aria-current');
    });
    if (push) history.pushState(null, '', url);
    scrollTo(0, 0);
    paint();
  } catch {
    location.href = url; // 取れなければふつうに移る
  }
}

function countUp(el, to) {
  if (reduce || to === 0) { el.textContent = to; return; }
  const t0 = performance.now(), dur = 900;
  const step = (now) => {
    const p = Math.min(1, (now - t0) / dur);
    const e = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(to * e);
    if (p < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}
