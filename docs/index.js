// 中身は data.json だけ。画面はそれを「段階 × 状態」の行列に置く
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const ymd = (d) => { const [y, m, day] = d.split('-'); return `${y}年${+m}月${+day}日`; };
const md = (d) => { const [, m, day] = d.split('-'); return `${+m}月${+day}日`; };
const mdShort = (d) => { const [, m, day] = d.split('-'); return `${+m}/${+day}`; };
const daysLeft = (d) => Math.max(0, Math.ceil((new Date(d + 'T23:59:59') - new Date()) / 86400000));
const STATE = { done: '済', now: 'いま', todo: 'これから' };
const pad2 = (n) => String(n).padStart(2, '0');

fetch('data.json')
  .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
  .then(render)
  .catch((e) => {
    $('main').insertAdjacentHTML('afterbegin', `<p role="alert" class="alert">data.json を読めませんでした（${esc(e.message)}）。</p>`);
  });

function render(d) {
  document.title = `${d.title} 開発ダッシュボード`;
  $('title').textContent = d.title;
  $('updated').textContent = ymd(d.updated);
  $('updated').dateTime = d.updated;
  $('goal').textContent = d.goal;
  $('pitch').textContent = d.pitch;

  // 次の節目
  $('next-label').textContent = d.next.label;
  $('next-due').textContent = md(d.next.due);
  $('next-due').dateTime = d.next.due;
  const left = daysLeft(d.next.due);
  $('next-left').innerHTML = `あと<b>${left}</b>日`;

  // 段階 × 状態
  const names = d.phases.map((p) => p.name);
  const nowName = (d.phases.find((p) => p.state === 'now') || d.phases[0]).name;
  const phaseOf = (name) => (names.includes(name) ? name : nowName);
  const qPhase = d.question_phases || {};
  const by = (list, key) => {
    const m = Object.fromEntries(names.map((n) => [n, []]));
    list.forEach((x) => m[phaseOf(key(x))].push(x));
    return m;
  };
  const decided = by(d.decisions, (x) => x.phase);
  const tasks = by(d.tasks, (x) => x.phase);
  const open = by(d.questions, (q) => qPhase[q]);

  const cell = (kind, label, items, row) => {
    if (!items.length) return `<div class="cell ${kind} empty" data-label="${label}"></div>`;
    return `<ul class="cell ${kind}" data-label="${label}" aria-label="${label}">${items.map(row).join('')}</ul>`;
  };

  // 広い画面の列幅: いちばん字の多いマスに応じて、段階の列を少し広くする
  const weight = (n) => {
    const chars = (xs, f) => xs.reduce((s, x) => s + f(x).length, 0);
    const most = Math.max(chars(decided[n], (x) => x.text), chars(tasks[n], (x) => x.text), chars(open[n], (q) => q));
    return (1 + Math.min(0.9, most / 90)).toFixed(2) + 'fr';
  };
  $('matrix').style.setProperty('--n', d.phases.length);
  $('matrix').style.setProperty('--cols', names.map((n) => `minmax(0, ${weight(n)})`).join(' '));
  $('phases').innerHTML = d.phases.map((p, i) => {
    const n = p.name;
    return `<li class="phase ${p.state}" style="--p:${i + 2}">
      <h3 class="ph-head"><span class="ph-no">${pad2(i + 1)}</span><span class="ph-nm">${esc(n)}</span><span class="ph-nt">${esc(p.note)}</span><span class="sr">（${STATE[p.state]}）</span></h3>
      ${cell('decided', '決めた', decided[n], (x) => `<li><time datetime="${x.date}">${mdShort(x.date)}</time><span>${esc(x.text)}</span></li>`)}
      ${cell('tasks', '作業', tasks[n], (t) => `<li class="${t.state}"><span class="sr">${STATE[t.state]}　</span><span>${esc(t.text)}</span></li>`)}
      ${cell('open', 'まだ', open[n], (q) => `<li><span>${esc(q)}</span></li>`)}
    </li>`;
  }).join('');

  // 小さな表
  $('climb').innerHTML = `<caption>${esc(d.climb.label)}<small>${esc(d.climb.note)}</small></caption>
    <thead><tr><th scope="col">押す人数</th><th scope="col" class="num">${esc(d.climb.unit)}</th></tr></thead>
    <tbody>${d.climb.rows.map((r) => `<tr><th scope="row">${r.people}人</th><td class="num">${r.sec}</td></tr>`).join('')}</tbody>`;
  $('places').innerHTML = `<caption>場所</caption>
    <tbody>${d.places.map((p) => `<tr><th scope="row">${esc(p.name)}</th><td>${esc(p.note)}</td></tr>`).join('')}</tbody>`;
  $('costs').innerHTML = `<caption>お金</caption>
    <thead><tr><th scope="col">項目</th><th scope="col" class="num">円</th><th scope="col">備考</th></tr></thead>
    <tbody>${d.costs.map((c) => `<tr><th scope="row">${esc(c.item)}</th><td class="num">${esc(c.yen)}</td><td>${esc(c.note)}</td></tr>`).join('')}</tbody>`;
  $('refs').innerHTML = `<caption>参考にするゲーム</caption>
    <tbody>${d.refs.map((r) => `<tr><th scope="row">${esc(r.name)}</th><td>${esc(r.note)}</td></tr>`).join('')}</tbody>`;

  $('origin').textContent = d.origin;
}
