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
  if ($('main').dataset.page !== 'art') return render(data);
  if (!data.art) throw new Error('data.json に art がない');
  renderArt(data.art); reveal();
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
