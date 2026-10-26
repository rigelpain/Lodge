// 3案で共通: data.json を読んで渡す
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (d) => { const [y, m, day] = d.split('-'); return `${y}年${+m}月${+day}日`; };
const short = (d) => { const [, m, day] = d.split('-'); return `${+m}/${+day}`; };
const daysLeft = (d) => Math.max(0, Math.ceil((new Date(d + 'T23:59:59') - new Date()) / 86400000));
const STATE = { done: '済', now: 'いま', todo: 'これから' };

function load(render) {
  fetch('../data.json')
    .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(render)
    .catch((e) => {
      document.body.insertAdjacentHTML('afterbegin', `<p role="alert" style="padding:16px">data.json を読めませんでした（${esc(e.message)}）。</p>`);
    });
}
