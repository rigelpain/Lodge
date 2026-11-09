// 軌跡: history.json を、まん中に背骨のある縦の道に描く。
// 上と横に同じ目次と絞り込みを置き、どちらで押しても同じ状態を書き換える
(() => {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const WEEK = '日月火水木金土';
  const KIND = { add: '追加', fix: '修正', tune: '調整', perf: '軽く', base: '土台' };
  const IMP = { 4: '節目', 3: '大', 2: '中', 1: '小' };
  const REPO = 'https://github.com/rigelpain/Lodge';
  const md = (d) => { const [, m, x] = d.split('-'); return `${+m}/${+x}`; };
  const wd = (d) => WEEK[new Date(d + 'T00:00:00').getDay()];
  const stars = (n) => '★'.repeat(n);

  let H, entries, days, state, cleanup = [];

  window.renderHistory = (h) => {
    cleanup.forEach((f) => f()); cleanup = [];
    H = h;
    entries = [...h.entries].sort((a, b) => a.date.localeCompare(b.date) || a.order - b.order);
    entries.forEach((e) => {
      e.chapter = h.chapters.find((c) => e.date >= c.from && e.date <= c.to)?.id || h.chapters[h.chapters.length - 1].id;
      e.text = [e.title, e.where, e.what, e.why, e.quote, e.result, e.left, e.pr ? `#${e.pr}` : '', ...(e.areas || [])].join(' ').toLowerCase();
    });
    days = [...new Set(entries.map((e) => e.date))];
    state = { imp: new Set(), kind: new Set(), area: new Set(), q: '' };

    hero();
    chapters();
    road();
    filters();
    apply();
    watch();
    jumpFromHash();
  };

  // ---- 上: 見出しと数 ----
  function hero() {
    $('hist-updated').dateTime = H.updated;
    $('hist-updated').textContent = (([y, m, d]) => `${y}年${+m}月${+d}日`)(H.updated.split('-'));
    $('hist-goal').textContent = H.hero.title;
    $('hist-pitch').textContent = H.hero.pitch;
    const n = (f) => entries.filter(f).length;
    const span = Math.round((new Date(days[days.length - 1]) - new Date(days[0])) / 86400000) + 1;
    const stats = [
      ['日数', span, '日', ''],
      ['PR', n((e) => e.pr), '本', ''],
      ['追加', n((e) => e.kind === 'add'), '件', 'k-add'],
      ['修正', n((e) => e.kind === 'fix'), '件', 'k-fix'],
      ['調整・軽く', n((e) => e.kind === 'tune' || e.kind === 'perf'), '件', 'k-tune'],
      ['節目', n((e) => e.importance === 4), '件', ''],
    ];
    $('hist-stats').innerHTML = stats.map(([t, v, u, k]) =>
      `<div class="${k}"><dt>${k ? '<i></i>' : ''}${esc(t)}</dt><dd><span class="num" data-to="${v}">${reduce ? v : 0}</span><small>${u}</small></dd></div>`).join('');
    if (!reduce) requestAnimationFrame(() => document.querySelectorAll('#hist-stats [data-to]').forEach((el) => countUp(el, +el.dataset.to)));
  }

  // ---- 目次: 章のカード、日ごとの棒、横の章と日 ----
  function chapters() {
    $('hist-chapters').innerHTML = H.chapters.map((c, i) =>
      `<li><a href="#${c.id}" data-jump="${c.id}"><span class="no">${String(i + 1).padStart(2, '0')}</span><span class="nm">${esc(c.title)}</span><span class="dt num">${md(c.from)}${c.to !== c.from ? `–${md(c.to)}` : ''}</span><span class="ct num" data-ch-count="${c.id}"></span></a></li>`).join('');
    const days$ = $('hist-days');
    days$.style.setProperty('--n', days.length);
    days$.innerHTML = days.map((d) =>
      `<button type="button" class="hist-day" role="listitem" data-jump="day-${d}" data-day="${d}" aria-label="${md(d)}（${wd(d)}）"><span class="n num"></span><span class="stack"></span><span class="lb">${md(d)}</span></button>`).join('');
    $('hist-legend').innerHTML = Object.entries(KIND).map(([k, t]) => `<span class="k-${k}"><i></i>${t}</span>`).join('');
    $('hist-toc').innerHTML = H.chapters.map((c, i) => {
      const ds = days.filter((d) => entries.some((e) => e.date === d && e.chapter === c.id));
      return `<li><a class="ch" href="#${c.id}" data-jump="${c.id}" data-ch="${c.id}"><span class="no">${String(i + 1).padStart(2, '0')}</span><span>${esc(c.title)}</span><span class="ct" data-ch-count="${c.id}"></span></a><ol>` +
        ds.map((d) => `<li><a class="dy" href="#day-${d}" data-jump="day-${d}" data-day="${d}"><b>${md(d)} <span class="wk">${wd(d)}</span> <span class="stars" data-day-star="${d}" ></span></b><span class="ct num" data-day-count="${d}"></span></a></li>`).join('') +
        '</ol></li>';
    }).join('');
  }

  // ---- 道 ----
  function road() {
    let html = '', lastDay = null, lastCh = null;
    entries.forEach((e) => {
      if (e.chapter !== lastCh) {
        const c = H.chapters.find((x) => x.id === e.chapter), i = H.chapters.indexOf(c);
        html += `<section class="hist-ch" id="${c.id}" data-ch="${c.id}"><div class="tile in"><p class="no">CHAPTER ${String(i + 1).padStart(2, '0')}</p><h2>${esc(c.title)}</h2><p class="dt num">${md(c.from)}${c.to !== c.from ? ` – ${md(c.to)}` : ''}</p><p class="sm">${esc(c.summary)}</p></div></section>`;
        lastCh = e.chapter;
      }
      if (e.date !== lastDay) {
        const [y, m, dd] = e.date.split('-');
        html += `<div class="hist-dayhead" id="day-${e.date}" data-day="${e.date}" role="separator" aria-label="${+m}月${+dd}日"><span class="dh"><time datetime="${e.date}"><b class="num">${+m}/${+dd}</b><i>${wd(e.date)}</i></time><small class="num"><span data-dh-count="${e.date}"></span> · ${y}</small></span></div>`;
        lastDay = e.date;
      }
      html += card(e);
    });
    $('hist-entries').innerHTML = html;
    if (!reduce) $('hist-road').classList.add('js-anim');
  }

  const hl = (s) => esc(s).replace(/(\d[\d,.]*\s*(?:[^\s\d→]{0,4})\s*→\s*\d[\d,.]*\s*[^\s、。）)]{0,4})/g, '<span class="num-hl">$1</span>');

  function card(e) {
    const link = e.pr
      ? `<a class="pr" href="${REPO}/pull/${e.pr}" target="_blank" rel="noopener">#${e.pr}</a>`
      : e.commits?.length ? `<a class="pr" href="${REPO}/commit/${e.commits[0]}" target="_blank" rel="noopener">${esc(e.commits[0])}${e.commits.length > 1 ? ` ほか ${e.commits.length - 1}` : ''}</a>` : '';
    const st = e.state === 'closed' ? '<span class="st closed">没</span>' : e.state === 'open' ? '<span class="st open">作業中</span>' : '';
    const whenTitle = e.pr ? (e.state === 'merged' ? 'マージした日時' : 'PR を作った日時') : 'コミットした日時';
    const when = `<time class="when num" datetime="${e.date}T${e.time || '00:00'}" title="${whenTitle}">${md(e.date)}（${wd(e.date)}）${e.time ? ` ${e.time}` : ''}</time>`;
    const meta = `<p class="meta">${when}<span class="kind">${KIND[e.kind] || e.kind}</span><span class="imp" title="重要度 ${IMP[e.importance]}">${stars(e.importance)}<b>${IMP[e.importance]}</b></span>${st}${(e.areas || []).map((a) => `<span class="area">${esc(a)}</span>`).join('')}${link}</p>`;
    const row = (cls, t, v) => v ? `<div class="${cls}"><dt>${t}</dt><dd>${v}</dd></div>` : '';
    const why = e.why || e.quote ? `${esc(e.why || '')}${e.quote ? `<p class="qt"><span>代表</span><q>${esc(e.quote.replace(/^「|」$/g, ''))}</q></p>` : ''}` : '';
    const body = `<dl class="body">${row('wh', 'どこで', esc(e.where))}${row('wt', 'なにを', esc(e.what))}${row('wy', 'なぜ', why)}${row('res', '結果', hl(e.result))}${row('left', '残り', esc(e.left))}</dl>`;
    const inner = e.importance === 1
      ? `<details><summary>${meta}<h3>${esc(e.title)}</h3></summary>${body}</details>`
      : `${meta}<h3>${esc(e.title)}</h3>${body}`;
    return `<article class="ev i${e.importance} k-${e.kind}" id="${esc(e.id)}" data-id="${esc(e.id)}">${e.importance === 4 ? '<span class="node" aria-hidden="true">★</span>' : '<span class="node" aria-hidden="true"></span>'}<div class="card">${inner}</div></article>`;
  }

  // ---- 絞り込み ----
  function filters() {
    const count = (key, v) => entries.filter((e) => key === 'area' ? e.areas?.includes(v) : String(e[key]) === String(v)).length;
    const areas = H.areas.filter((a) => count('area', a));
    const group = (name, key, items) => `<fieldset><legend>${name}</legend><div class="hist-chips">` +
      items.map(([v, label, cls]) => `<button type="button" class="hist-chip ${cls || ''}" data-key="${key}" data-v="${esc(v)}" aria-pressed="false">${label}<span class="c num">${count(key === 'imp' ? 'importance' : key, v)}</span></button>`).join('') + '</div></fieldset>';
    const html = group('重要度', 'imp', [4, 3, 2, 1].map((n) => [n, `<span class="stars" aria-hidden="true">${stars(n)}</span>${IMP[n]}`]))
      + group('種類', 'kind', Object.entries(KIND).map(([k, t]) => [k, `<i></i>${t}`, `k-${k}`]))
      + group('分野', 'area', areas.map((a) => [a, esc(a)]))
      + `<fieldset><legend>ことばで探す</legend><div class="hist-search"><input type="search" placeholder="例: 雪玉、fps、#90" aria-label="ことばで探す"><button type="button" class="hist-reset" disabled>すべて出す</button></div></fieldset>`;
    document.querySelectorAll('.hist-filter').forEach((f) => { f.innerHTML = html; });

    const main = $('main');
    const onClick = (ev) => {
      const chip = ev.target.closest('.hist-chip');
      if (chip) {
        const set = state[chip.dataset.key], v = chip.dataset.key === 'imp' ? +chip.dataset.v : chip.dataset.v;
        set.has(v) ? set.delete(v) : set.add(v);
        apply(); return;
      }
      if (ev.target.closest('.hist-reset')) {
        state.imp.clear(); state.kind.clear(); state.area.clear(); state.q = '';
        apply(); return;
      }
      const j = ev.target.closest('[data-jump]');
      if (j) { ev.preventDefault(); jump(j.dataset.jump); }
    };
    let t;
    const onInput = (ev) => {
      if (!ev.target.matches('.hist-search input')) return;
      state.q = ev.target.value.trim().toLowerCase();
      clearTimeout(t); t = setTimeout(apply, 120);
    };
    main.addEventListener('click', onClick);
    main.addEventListener('input', onInput);
    cleanup.push(() => { main.removeEventListener('click', onClick); main.removeEventListener('input', onInput); });
  }

  const passes = (e) =>
    (!state.imp.size || state.imp.has(e.importance)) &&
    (!state.kind.size || state.kind.has(e.kind)) &&
    (!state.area.size || e.areas?.some((a) => state.area.has(a))) &&
    (!state.q || state.q.split(/\s+/).every((w) => e.text.includes(w.replace(/^＃/, '#'))));

  function apply() {
    // 絞り込みの見た目を 2 か所ともそろえる
    document.querySelectorAll('.hist-chip').forEach((c) => {
      const v = c.dataset.key === 'imp' ? +c.dataset.v : c.dataset.v;
      c.setAttribute('aria-pressed', state[c.dataset.key].has(v));
    });
    document.querySelectorAll('.hist-search input').forEach((i) => { if (i !== document.activeElement) i.value = state.q; });
    const any = state.imp.size || state.kind.size || state.area.size || state.q;
    document.querySelectorAll('.hist-reset').forEach((b) => { b.disabled = !any; });

    const shown = entries.filter(passes), ids = new Set(shown.map((e) => e.id));
    const txt = `${shown.length} / ${entries.length} 件`;
    $('hist-count-top').textContent = txt; $('hist-count-side').textContent = txt;
    $('hist-empty').hidden = shown.length > 0;

    // 道: 出すものだけ残し、日の札と章も中身がなければ隠す
    const byDay = {}, byCh = {};
    shown.forEach((e) => { (byDay[e.date] ||= []).push(e); byCh[e.chapter] = (byCh[e.chapter] || 0) + 1; });
    document.querySelectorAll('#hist-entries .ev').forEach((el) => { el.hidden = !ids.has(el.dataset.id); });
    document.querySelectorAll('#hist-entries .hist-dayhead').forEach((el) => { el.hidden = !byDay[el.dataset.day]; });
    document.querySelectorAll('#hist-entries .hist-ch').forEach((el) => { el.hidden = !byCh[el.dataset.ch]; });
    document.querySelectorAll('[data-dh-count]').forEach((el) => { el.textContent = `${byDay[el.dataset.dhCount]?.length || 0} 件`; });

    // 目次の数
    document.querySelectorAll('[data-ch-count]').forEach((el) => {
      const n = byCh[el.dataset.chCount] || 0;
      el.textContent = `${n} 件`;
      el.closest('a').classList.toggle('zero', !n);
    });
    document.querySelectorAll('[data-day-count]').forEach((el) => {
      const n = byDay[el.dataset.dayCount]?.length || 0;
      el.textContent = n; el.closest('a').classList.toggle('zero', !n);
    });
    document.querySelectorAll('[data-day-star]').forEach((el) => {
      const has = (byDay[el.dataset.dayStar] || []).some((e) => e.importance === 4);
      el.textContent = has ? '★' : '';
      if (has) el.title = '節目のある日'; else el.removeAttribute('title');
    });
    // 日ごとの棒: 全部の日のいちばん多い日を高さ 100% として、種類ごとに積む
    const max = Math.max(...days.map((d) => entries.filter((e) => e.date === d).length));
    document.querySelectorAll('.hist-day').forEach((b) => {
      const list = byDay[b.dataset.day] || [];
      b.querySelector('.n').textContent = list.length || '';
      b.querySelector('.stack').style.height = `${(list.length / max) * 100}%`;
      b.querySelector('.stack').innerHTML = Object.keys(KIND).map((k) => {
        const n = list.filter((e) => e.kind === k).length;
        return n ? `<i class="k-${k}" style="height:${(n / list.length) * 100}%"></i>` : '';
      }).join('');
      b.disabled = !list.length;
      b.setAttribute('aria-label', `${md(b.dataset.day)}（${wd(b.dataset.day)}） ${list.length} 件`);
    });

    sides();
  }

  // 左右に振り分け、向かいの札と少し重ねて詰める（重ねても同じ側どうしはぶつからない高さのときだけ）
  function sides() {
    let r = false, prev = null;
    document.querySelectorAll('#hist-entries > *').forEach((el) => {
      if (el.hidden) return;
      if (!el.classList.contains('ev') || el.classList.contains('i4')) { prev = null; r = false; return; }
      el.classList.toggle('r', r);
      el.classList.remove('lap');
      el._prev = prev;
      prev = el; r = !r;
    });
    if (matchMedia('(max-width: 760px)').matches) return;
    // 高さを先にまとめて読み、あとでまとめて書く（読み書きを交互にしない）
    const evs = [...document.querySelectorAll('#hist-entries > .ev:not([hidden])')];
    const laps = evs.map((el) => el._prev && el._prev.querySelector('.card').offsetHeight >= 78);
    evs.forEach((el, i) => { if (laps[i]) el.classList.add('lap'); });
  }

  // ---- 動き: 札が入ってくる・背骨が伸びる・目次のいまいる所 ----
  function watch() {
    if (!reduce && 'IntersectionObserver' in window) {
      const io = new IntersectionObserver((xs) => xs.forEach((x) => {
        if (x.isIntersecting) { x.target.classList.add('seen'); io.unobserve(x.target); }
      }), { rootMargin: '0px 0px -8% 0px' });
      document.querySelectorAll('#hist-entries .ev').forEach((el) => io.observe(el));
      cleanup.push(() => io.disconnect());
    } else {
      document.querySelectorAll('#hist-entries .ev').forEach((el) => el.classList.add('seen'));
    }

    let ticking = false, curDay = null;
    const update = () => {
      ticking = false;
      const road = $('hist-road');
      if (!road) return;
      const rr = road.getBoundingClientRect(), vh = innerHeight;
      const p = Math.min(1, Math.max(0, (vh * 0.6 - rr.top) / rr.height));
      $('hist-spine-fill').style.height = `${(p * 100).toFixed(2)}%`;
      $('hist-progress').style.width = `${(p * 100).toFixed(1)}%`;
      // いまいる日: 画面の上 35% より上にある最後の日の札
      let day = null;
      for (const el of document.querySelectorAll('#hist-entries .hist-dayhead:not([hidden])')) {
        if (el.getBoundingClientRect().top < vh * 0.35) day = el.dataset.day; else break;
      }
      if (day === curDay) return;
      curDay = day;
      const ch = day && entries.find((e) => e.date === day)?.chapter;
      const now = $('hist-now');
      if (now) {
        now.classList.toggle('on', !!day);
        if (day) now.innerHTML = `<span class="pill"><b class="num">${md(day)}</b><i>${wd(day)}</i><span>${esc(H.chapters.find((c) => c.id === ch)?.title || '')}</span></span>`;
      }
      document.querySelectorAll('.hist-toc .dy, .hist-day').forEach((a) => a.classList.toggle('on', a.dataset.day === day));
      document.querySelectorAll('.hist-toc .ch').forEach((a) => a.classList.toggle('on', a.dataset.ch === ch));
      document.querySelectorAll('.hist-chapters a').forEach((a) => a.classList.toggle('on', a.dataset.jump === ch));
      // 横の目次の中で、いまの日が見える所まで送る（ページは動かさない）
      const side = document.querySelector('.hist-side'), on = side?.querySelector('.dy.on');
      if (side && on) {
        const s = side.getBoundingClientRect(), o = on.getBoundingClientRect();
        if (o.top < s.top + 60 || o.bottom > s.bottom - 40) side.scrollTo({ top: side.scrollTop + (o.top - s.top) - s.height / 3, behavior: reduce ? 'auto' : 'smooth' });
      }
    };
    const onScroll = () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
    addEventListener('scroll', onScroll, { passive: true });
    addEventListener('resize', onScroll, { passive: true });
    cleanup.push(() => { removeEventListener('scroll', onScroll); removeEventListener('resize', onScroll); });
    update();
  }

  // 目次から飛ぶ。ハッシュは書き換えるだけにする（index.js は popstate でページを読み直すため）
  function jump(id) {
    const el = document.getElementById(id);
    if (!el || el.hidden) return;
    el.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
    history.replaceState(null, '', `#${id}`);
  }
  function jumpFromHash() {
    const id = decodeURIComponent(location.hash.slice(1));
    if (!id) return;
    const el = document.getElementById(id);
    if (!el) return;
    const go = () => el.scrollIntoView({ block: el.classList.contains('ev') ? 'center' : 'start' });
    go();
    document.fonts?.ready.then(go);
    setTimeout(() => {
      if (el.classList.contains('ev')) {
        el.classList.add('seen', 'hit');
        el.querySelector('details')?.setAttribute('open', '');
        setTimeout(() => el.classList.remove('hit'), 2000);
      }
    }, 50);
  }

  function countUp(el, to) {
    if (!to) { el.textContent = to; return; }
    const t0 = performance.now(), dur = 1100;
    const step = (now) => {
      const p = Math.min(1, (now - t0) / dur);
      el.textContent = Math.round(to * (1 - Math.pow(1 - p, 3)));
      if (p < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }
})();
