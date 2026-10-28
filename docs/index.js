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
