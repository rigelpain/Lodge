// テストプレイのページ: GitHub Releases の playtest-* の版を読んで、ダウンロードのボタンと前の版を描く。
// 版を載せるのは publish_playtest.sh。タグは playtest-<YYYY-MM-DD>-<短いコミット>
(() => {
  const REPO = 'rigelpain/Lodge';
  const PAGE = `https://github.com/${REPO}/releases`;
  const q = (id) => document.getElementById(id);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const mb = (n) => `${Math.round(n / 1048576)} MB`;
  const FILES = { win: 'Lodge-windows.zip', mac: 'Lodge-mac.zip' };
  const OS_NAME = { win: 'Windows', mac: 'Mac（Apple シリコン）' };

  // 見ている人のパソコン。わからなければ Windows
  const guessOS = () => {
    const p = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || navigator.userAgent;
    return /mac/i.test(p) ? 'mac' : 'win';
  };

  // タグから日付とコミットを取る
  const parseTag = (tag) => {
    const m = /^playtest-(\d{4})-(\d{2})-(\d{2})-([0-9a-f]+)/.exec(tag);
    return m ? { date: `${m[1]}年${+m[2]}月${+m[3]}日`, md: `${+m[2]}/${+m[3]}`, sha: m[4] } : { date: tag, md: tag, sha: '' };
  };

  function setOS(os) {
    document.querySelectorAll('.pt-os-btn').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.os === os)));
    document.querySelectorAll('.pt-how[data-os]').forEach((l) => { l.hidden = l.dataset.os !== os; });
    document.querySelectorAll('.pt-get').forEach((a) => a.classList.toggle('main', a.dataset.os === os));
  }

  function bind() {
    const main = q('main');
    if (main.dataset.ptBound) return;
    main.dataset.ptBound = '1';
    main.addEventListener('click', (e) => {
      const os = e.target.closest('.pt-os-btn');
      if (os) { setOS(os.dataset.os); return; }
      const cp = e.target.closest('.pt-copy');
      if (cp && navigator.clipboard) {
        navigator.clipboard.writeText(cp.dataset.copy).then(() => {
          cp.textContent = '写した';
          setTimeout(() => { cp.textContent = '写す'; }, 1600);
        }, () => {});
      }
    });
  }

  function assetsOf(rel) {
    const out = {};
    for (const [os, name] of Object.entries(FILES)) {
      const a = (rel.assets || []).find((x) => x.name === name);
      if (a) out[os] = a;
    }
    return out;
  }

  function paintLatest(rel, os) {
    const t = parseTag(rel.tag_name);
    const as = assetsOf(rel);
    const btns = ['win', 'mac'].filter((k) => as[k]).map((k) => `
      <a class="pt-get${k === os ? ' main' : ''}" data-os="${k}" href="${esc(as[k].browser_download_url)}" download>
        <span class="pt-get-os">${OS_NAME[k]}</span>
        <span class="pt-get-sub">${esc(as[k].name)} · ${mb(as[k].size)}</span>
      </a>`).join('');
    const count = Object.values(as).reduce((s, a) => s + (a.download_count || 0), 0);
    q('pt-latest').innerHTML = `
      <p class="pt-ver"><span class="num">${esc(t.md)}</span><span class="pt-ver-sub">${esc(t.date)}<br>コミット <a href="https://github.com/${REPO}/commit/${esc(t.sha)}"><code>${esc(t.sha)}</code></a></span></p>
      <div class="pt-gets">${btns || `<p>zip がまだ載っていません。<a href="${esc(rel.html_url)}">版のページ</a></p>`}</div>
      <p class="cap">ダウンロード <span class="num">${count}</span> 回 · <a href="${esc(rel.html_url)}">版のページ</a></p>`;
  }

  function paintNotes(rel) {
    const lines = String(rel.body || '').split('\n').map((s) => s.trim()).filter((s) => /^[-*] /.test(s)).map((s) => s.slice(2));
    q('pt-notes').innerHTML = lines.length
      ? lines.map((s) => `<li><span class="mark" aria-hidden="true"></span><span>${esc(s)}</span></li>`).join('')
      : '<li><span class="mark" aria-hidden="true"></span><span>書いてありません。</span></li>';
  }

  function paintOld(list) {
    q('pt-old').innerHTML = list.length
      ? list.map((rel) => {
        const t = parseTag(rel.tag_name);
        const as = assetsOf(rel);
        const links = ['win', 'mac'].filter((k) => as[k]).map((k) => `<a href="${esc(as[k].browser_download_url)}">${k === 'win' ? 'Windows' : 'Mac'}</a>`).join('　');
        return `<li class="done"><span class="mark" aria-hidden="true"></span><span><b>${esc(t.date)}</b> <code>${esc(t.sha)}</code><span class="sn">${links}</span></span></li>`;
      }).join('')
      : '<li><span class="mark" aria-hidden="true"></span><span>まだありません。</span></li>';
  }

  window.renderPlaytest = async function () {
    bind();
    const os = guessOS();
    setOS(os);
    try {
      const r = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, { headers: { Accept: 'application/vnd.github+json' } });
      if (!r.ok) throw new Error(r.status === 403 ? 'GitHub に何度も聞きすぎました。少し待って開き直してください' : `GitHub が ${r.status} を返しました`);
      const all = (await r.json()).filter((x) => !x.draft && x.tag_name.startsWith('playtest-'));
      if (!all.length) {
        q('pt-latest').innerHTML = '<p class="pt-wait">まだ配っている版がありません。</p>';
        paintNotes({ body: '' });
        paintOld([]);
        return;
      }
      paintLatest(all[0], os);
      paintNotes(all[0]);
      paintOld(all.slice(1, 11));
    } catch (e) {
      q('pt-latest').innerHTML = `<p class="pt-wait" role="alert">版の一覧を読めませんでした（${esc(e.message)}）。<a href="${PAGE}">GitHub の Releases</a> から取ってください。</p>`;
    }
  };
})();
