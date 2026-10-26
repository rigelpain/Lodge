// data.json から図を組む
load((d) => {
  $('updated').textContent = fmt(d.updated) + ' 更新';
  $('goal').textContent = d.goal;

  // 1. 道のり
  const track = $('track');
  track.style.setProperty('--n', d.phases.length);
  track.innerHTML = d.phases.map((p, i) =>
    `<li class="${p.state}"${p.state === 'now' ? ' aria-current="step"' : ''}><span class="no num">${String(i + 1).padStart(2, '0')}</span><span class="nm">${esc(p.name)}</span><span class="nt">${esc(p.note)}</span></li>`).join('');

  // 2. 次の節目: 最後に決めた日から節目の日までを1日1マスに
  $('next').textContent = d.next.label;
  const left = daysLeft(d.next.due);
  $('days').textContent = left;
  $('days').className = 'num';
  const startS = d.decisions[d.decisions.length - 1].date;
  const day = (s) => new Date(s + 'T00:00:00');
  const total = Math.round((day(d.next.due) - day(startS)) / 86400000) + 1;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const passed = Math.round((today - day(startS)) / 86400000);
  const line = $('dayline');
  line.style.setProperty('--days', total);
  line.innerHTML = Array.from({ length: total }, (_, i) => `<li class="${i < passed ? 'past' : i === passed ? 'today' : ''}"></li>`).join('');
  $('daycap').textContent = `${short(startS)} から ${short(d.next.due)} まで。赤が今日`;

  // 3. 計測: 一番長い時間を幅いっぱいとして比べる
  if (d.climb) {
    $('climb-h').textContent = d.climb.label;
    const max = Math.max(...d.climb.rows.map((r) => r.sec));
    const fastest = Math.min(...d.climb.rows.map((r) => r.sec));
    $('bars').innerHTML = d.climb.rows.map((r) =>
      `<div class="bar${r.sec === fastest ? ' fast' : ''}" style="--w:${(r.sec / max * 82).toFixed(1)}%"><span class="who">${r.people}人</span><span class="rail"><span class="fill"></span><span class="val">${r.sec}<small>${esc(d.climb.unit)}</small></span></span></div>`).join('');
    $('climbcap').textContent = d.climb.note;
  }

  // 4. 作業: いま → これから → 済の順。点は同じ順で
  const order = { now: 0, todo: 1, done: 2 };
  const tasks = [...d.tasks].sort((a, b) => order[a.state] - order[b.state]);
  const done = tasks.filter((t) => t.state === 'done').length;
  $('tasks-h').textContent = `作業　${done} / ${tasks.length} 済`;
  $('dots').innerHTML = [...tasks].reverse().map((t) => `<i class="${t.state}"></i>`).join('');
  $('tasks').innerHTML = tasks.map((t) => `<li class="${t.state}"><span class="k">${STATE[t.state]}</span><span>${esc(t.text)}</span></li>`).join('');

  // 5. 決めたこと: 最初の決定から節目までの軸に、日ごとに点を積む
  const a0 = day(d.decisions[0].date), a1 = day(d.next.due);
  const span = a1 - a0 || 1;
  const pos = (s) => ((day(s) - a0) / span * 100).toFixed(2) + '%';
  const byDate = {};
  for (const x of d.decisions) (byDate[x.date] ||= []).push(x);
  let ax = Object.entries(byDate).map(([s, xs]) =>
    `<span class="stack" style="left:${pos(s)}">${xs.map(() => '<i></i>').join('')}</span><span class="tick" style="left:${pos(s)}">${short(s)}</span>`).join('');
  ax += `<span class="stack" style="left:100%"><i class="n"></i></span><span class="tick" style="left:100%;color:var(--red)">${short(d.next.due)}</span>`;
  $('axis').innerHTML = ax;
  // いちばん多く積んだ日に合わせて軸の高さを取る（見出しにかぶらないように）
  const most = Math.max(...Object.values(byDate).map((xs) => xs.length));
  $('axis').style.height = `calc(${most} * (clamp(8px, 0.9vw, 14px) + 3px) + clamp(16px, 2vw, 32px))`;
  $('decisions').innerHTML = [...d.decisions].reverse().map((x) => `<li><span class="k num">${short(x.date)}</span><span>${esc(x.text)}</span></li>`).join('');

  // 6・7
  $('questions').innerHTML = d.questions.map((q) => `<li><span>${esc(q)}</span></li>`).join('');
  $('places').innerHTML = d.places.map((p) => `<dt>${esc(p.name)}</dt><dd>${esc(p.note)}</dd>`).join('');
  $('costs').innerHTML = d.costs.map((c) => `<dt>${esc(c.item)}</dt><dd class="amount">${esc(c.yen)}<span style="font-size:var(--t-xs);color:var(--ink-2)">${/\d/.test(c.yen) ? ' 円' : ''}　${esc(c.note)}</span></dd>`).join('');
  $('refs').innerHTML = d.refs.map((r) => `<dt>${esc(r.name)}</dt><dd>${esc(r.note)}</dd>`).join('');
  $('origin').textContent = d.origin;
}, 'data.json');
