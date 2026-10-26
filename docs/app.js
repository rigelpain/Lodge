// docs/data.json を読んで札を埋める
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmtDate = (d) => { const [y, m, day] = d.split('-'); return `${y}年${+m}月${+day}日`; };
const STATE_ICON = { done: 'ph-check-circle', now: 'ph-arrow-circle-right', todo: 'ph-circle' };
const STATE_TEXT = { done: '済', now: '進行中', todo: 'これから' };

// 読み込み中は形だけ出す
for (const id of ['tasks', 'decisions', 'questions']) $(id).innerHTML = '<li><span class="skeleton"></span></li>'.repeat(3);

fetch('data.json')
  .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
  .then(render)
  .catch((e) => {
    $('main').insertAdjacentHTML('afterbegin',
      `<p class="card span-12" role="alert">data.json を読めませんでした（${esc(e.message)}）。ファイルを直接開いた場合は、GitHub Pages か手元のサーバーで開いてください。</p>`);
  });

function render(d) {
  $('title').textContent = d.title;
  $('goal').textContent = d.goal;
  $('pitch').textContent = d.pitch;
  $('origin').textContent = d.origin;

  $('next-label').textContent = d.next.label;
  $('next-due').dateTime = d.next.due;
  $('next-due').textContent = fmtDate(d.next.due);
  const days = Math.ceil((new Date(d.next.due + 'T23:59:59') - new Date()) / 86400000);
  $('next-days').textContent = Math.max(0, days);

  $('phases').innerHTML = d.phases.map((p) =>
    `<li class="${p.state}"${p.state === 'now' ? ' aria-current="step"' : ''}><span class="name">${esc(p.name)}</span><span class="note">${esc(p.note)}</span></li>`).join('');

  $('tasks').innerHTML = d.tasks.map((t) =>
    `<li class="${t.state}"><i class="ph ${STATE_ICON[t.state]}" aria-hidden="true"></i><span><span class="sr">${STATE_TEXT[t.state]}: </span>${esc(t.text)}</span></li>`).join('');

  $('decisions').innerHTML = [...d.decisions].reverse().map((x) =>
    `<li><time datetime="${x.date}">${fmtDate(x.date)}</time>${esc(x.text)}</li>`).join('');

  $('questions').innerHTML = d.questions.map((q) => `<li>${esc(q)}</li>`).join('');

  $('places').innerHTML = d.places.map((p) => `<div><dt>${esc(p.name)}</dt><dd>${esc(p.note)}</dd></div>`).join('');

  $('costs').innerHTML = d.costs.map((c) =>
    `<tr><td>${esc(c.item)}<small>${esc(c.note)}</small></td><td>${esc(c.yen)}</td></tr>`).join('');

  $('refs').innerHTML = d.refs.map((r) => `<li><b>${esc(r.name)}</b><span>${esc(r.note)}</span></li>`).join('');

  $('updated').dateTime = d.updated;
  $('updated').textContent = fmtDate(d.updated);
}
