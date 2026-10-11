"""Phone remote for Sonero TV, served by the TV server at GET /.

Self-contained (no external assets) so it works on a LAN without internet.
Pairs with the same 6-digit PIN as a TV (kind "remote"); the token lives in
the phone browser's localStorage.
"""

REMOTE_PAGE_HTML = """<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0f0f12">
<title>Sonero Remote</title>
<style>
  :root { --bg:#0f0f12; --surface:#1a1a1f; --alt:#232329; --border:#2e2e36; --text:#f4f4f6;
          --muted:#9a9aa6; --accent:#7c4dff; --err:#ff5c6c; }
  * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
  html,body { margin:0; background:var(--bg); color:var(--text);
    font:15px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  main { max-width:560px; margin:0 auto; padding:16px 16px 40px; }
  header { display:flex; align-items:center; gap:10px; margin-bottom:16px; }
  .logo { width:34px; height:34px; border-radius:10px; background:var(--accent); display:grid;
    place-items:center; font-weight:800; color:#fff; }
  h1 { font-size:17px; margin:0; } .muted { color:var(--muted); font-size:13px; }
  .card { background:var(--surface); border:1px solid var(--border); border-radius:16px; padding:16px; }
  .hidden { display:none !important; }
  input, select { width:100%; padding:12px; border-radius:10px; border:1px solid var(--border);
    background:var(--alt); color:var(--text); font-size:16px; }
  .pin { font-size:28px; letter-spacing:10px; text-align:center; }
  button { border:0; border-radius:12px; background:var(--alt); color:var(--text); font-size:15px;
    padding:12px 16px; cursor:pointer; }
  button.primary { background:var(--accent); color:#fff; font-weight:600; }
  button:disabled { opacity:.4; }
  .full { width:100%; margin-top:12px; }
  .np { display:flex; gap:14px; align-items:center; }
  .np img, .ph { width:76px; height:76px; border-radius:10px; object-fit:cover; background:var(--alt); flex:none; }
  .np .t { font-weight:600; font-size:16px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .np .a { color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .bar { height:5px; border-radius:5px; background:var(--border); margin:14px 0 4px; overflow:hidden; }
  .bar i { display:block; height:100%; width:0; background:var(--accent); }
  .times { display:flex; justify-content:space-between; font-size:12px; color:var(--muted); }
  .controls { display:flex; justify-content:center; align-items:center; gap:14px; margin-top:12px; }
  .controls button { width:56px; height:56px; border-radius:50%; font-size:22px; padding:0; }
  .controls .play { width:68px; height:68px; background:var(--accent); color:#fff; font-size:26px; }
  .controls .on { color:var(--accent); }
  .vol { display:flex; align-items:center; gap:10px; margin-top:14px; }
  .vol input { padding:0; accent-color:var(--accent); }
  ul { list-style:none; margin:12px 0 0; padding:0; }
  li { display:flex; gap:12px; align-items:center; padding:8px; border-radius:10px; cursor:pointer; }
  li:active, li.cur { background:var(--alt); }
  li img, li .ph { width:44px; height:44px; border-radius:6px; }
  li .tt { min-width:0; } li .t { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  li .a { color:var(--muted); font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .err { color:var(--err); font-size:14px; margin-top:10px; }
  .row { display:flex; gap:8px; margin-top:12px; }
  .row > * { flex:1; }
</style>
</head>
<body>
<main>
  <header>
    <div class="logo">S</div>
    <div><h1>Sonero Remote</h1><div class="muted" id="server">Control para Sonero TV</div></div>
  </header>

  <!-- Pairing -->
  <section id="pairView" class="card hidden">
    <p style="margin-top:0">En tu computadora abre Sonero → Compartir → TV y pulsa <b>Emparejar</b>. Escribe aquí el PIN:</p>
    <input id="pin" class="pin" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="••••••">
    <button id="pairBtn" class="primary full">Emparejar</button>
    <div id="pairErr" class="err"></div>
  </section>

  <!-- Remote -->
  <section id="remoteView" class="hidden">
    <div id="noTv" class="card hidden">
      <b>No hay ninguna TV conectada.</b>
      <p class="muted">Abre Sonero TV en el televisor. Debe estar en la misma red WiFi.</p>
    </div>
    <div id="tvBox" class="hidden">
      <select id="tvSelect" class="hidden" style="margin-bottom:12px"></select>
      <div class="card">
        <div class="np">
          <img id="npCover" class="hidden" alt="">
          <div id="npPh" class="ph"></div>
          <div style="min-width:0">
            <div class="t" id="npTitle">Nada en reproducción</div>
            <div class="a" id="npArtist"></div>
            <div class="muted" id="npTv"></div>
          </div>
        </div>
        <div class="bar"><i id="npBar"></i></div>
        <div class="times"><span id="npPos">0:00</span><span id="npDur">0:00</span></div>
        <div class="controls">
          <button id="shuffleBtn" title="Aleatorio">⤮</button>
          <button data-cmd="previous" title="Anterior">⏮</button>
          <button id="playBtn" class="play" data-cmd="toggle" title="Reproducir/Pausa">▶</button>
          <button data-cmd="next" title="Siguiente">⏭</button>
          <button id="fwdBtn" title="+15 s">⟳</button>
        </div>
        <div class="vol"><span>🔈</span><input id="vol" type="range" min="0" max="100" value="100"><span>🔊</span></div>
      </div>
      <div class="row">
        <input id="search" type="search" placeholder="Buscar canción o artista">
      </div>
      <div class="row">
        <button id="playAll" class="primary">Reproducir todo</button>
        <button id="shuffleAll">Aleatorio</button>
      </div>
      <ul id="list"></ul>
    </div>
    <div id="err" class="err"></div>
  </section>
</main>
<script>
(function () {
  var KEY = "sonero_remote_token";
  var token = null;
  try { token = localStorage.getItem(KEY); } catch (e) {}
  var tracks = [], tvs = [], tvId = null, state = null, dragging = false;
  var $ = function (id) { return document.getElementById(id); };

  function show(view) {
    $("pairView").classList.toggle("hidden", view !== "pair");
    $("remoteView").classList.toggle("hidden", view !== "remote");
  }
  function fmt(s) { s = Math.max(0, Math.round(s || 0)); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2); }
  function api(path, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ "Content-Type": "application/json" }, opts.headers || {});
    if (token) opts.headers.Authorization = "Bearer " + token;
    return fetch(path, opts).then(function (r) {
      if (r.status === 401) { forget(); throw new Error("unauthorized"); }
      return r.json().then(function (j) { if (!r.ok) throw new Error(j.detail || r.statusText); return j; });
    });
  }
  function forget() { token = null; try { localStorage.removeItem(KEY); } catch (e) {} show("pair"); }
  function cover(id) { return "/tv/cover/" + id + "?t=" + encodeURIComponent(token); }

  // ── Pairing ──
  $("pairBtn").onclick = function () {
    var pin = $("pin").value.replace(/\\D/g, "");
    $("pairErr").textContent = "";
    fetch("/tv/pair", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pin: pin, device_name: "Control (" + (navigator.platform || "celular") + ")", kind: "remote" }) })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.detail || "Error"); return j; }); })
      .then(function (j) { token = j.token; try { localStorage.setItem(KEY, token); } catch (e) {} start(); })
      .catch(function (e) { $("pairErr").textContent = e.message; });
  };
  $("pin").addEventListener("input", function () { if (this.value.replace(/\\D/g, "").length === 6) $("pairBtn").click(); });

  // ── Remote ──
  function send(body) {
    if (!tvId) return Promise.resolve();
    return api("/tv/remote/devices/" + tvId + "/command", { method: "POST", body: JSON.stringify(body) })
      .then(function () { $("err").textContent = ""; setTimeout(poll, 300); })
      .catch(function (e) { if (e.message !== "unauthorized") $("err").textContent = e.message; });
  }
  Array.prototype.forEach.call(document.querySelectorAll("[data-cmd]"), function (b) {
    b.onclick = function () { send({ action: b.getAttribute("data-cmd") }); };
  });
  $("shuffleBtn").onclick = function () { send({ action: "shuffle", shuffle: !(state && state.shuffle) }); };
  $("fwdBtn").onclick = function () { if (state) send({ action: "seek", position: (state.position || 0) + 15 }); };
  $("vol").addEventListener("input", function () { dragging = true; });
  $("vol").addEventListener("change", function () { dragging = false; send({ action: "volume", value: this.value / 100 }); });
  $("tvSelect").onchange = function () { tvId = this.value; render(); };

  function visible() {
    var q = $("search").value.trim().toLowerCase();
    if (!q) return tracks;
    return tracks.filter(function (t) { return (t.title + " " + t.artist + " " + t.album).toLowerCase().indexOf(q) >= 0; });
  }
  function playList(list, index, shuffle) {
    if (!list.length) return;
    send({ action: "play", track_ids: list.map(function (t) { return t.id; }), index: index || 0, shuffle: !!shuffle });
  }
  $("playAll").onclick = function () { playList(visible(), 0, false); };
  $("shuffleAll").onclick = function () { playList(visible(), 0, true); };
  $("search").addEventListener("input", renderList);

  function renderList() {
    var list = visible(), ul = $("list"), cur = state && state.track_id;
    ul.innerHTML = "";
    list.slice(0, 300).forEach(function (t, i) {
      var li = document.createElement("li");
      if (t.id === cur) li.className = "cur";
      li.innerHTML = (t.has_cover ? '<img loading="lazy" alt="">' : '<div class="ph"></div>') +
        '<div class="tt"><div class="t"></div><div class="a"></div></div>';
      if (t.has_cover) li.querySelector("img").src = cover(t.id);
      li.querySelector(".t").textContent = t.title;
      li.querySelector(".a").textContent = t.artist;
      li.onclick = function () { playList(list, i, false); };
      ul.appendChild(li);
    });
  }

  function render() {
    $("noTv").classList.toggle("hidden", tvs.length > 0);
    $("tvBox").classList.toggle("hidden", tvs.length === 0);
    $("tvSelect").classList.toggle("hidden", tvs.length < 2);
    var tv = tvs.filter(function (d) { return d.id === tvId; })[0];
    state = tv ? tv.now_playing : null;
    $("npTv").textContent = tv ? "📺 " + tv.name : "";
    var s = state || {};
    $("npTitle").textContent = s.title || "Nada en reproducción";
    $("npArtist").textContent = s.artist || "";
    var hasCover = s.track_id && s.has_cover;
    $("npCover").classList.toggle("hidden", !hasCover);
    $("npPh").classList.toggle("hidden", !!hasCover);
    if (hasCover && $("npCover").getAttribute("data-id") !== s.track_id) {
      $("npCover").src = cover(s.track_id); $("npCover").setAttribute("data-id", s.track_id);
    }
    $("npBar").style.width = (s.duration ? Math.min(100, 100 * s.position / s.duration) : 0) + "%";
    $("npPos").textContent = fmt(s.position); $("npDur").textContent = fmt(s.duration);
    $("playBtn").textContent = s.playing ? "⏸" : "▶";
    $("shuffleBtn").classList.toggle("on", !!s.shuffle);
    if (!dragging && s.volume != null) $("vol").value = Math.round(s.volume * 100);
    Array.prototype.forEach.call($("list").children, function () {});
  }

  var lastTrack = null;
  function poll() {
    return api("/tv/remote/devices").then(function (j) {
      $("server").textContent = j.server_name;
      tvs = j.tvs;
      if (!tvs.some(function (d) { return d.id === tvId; })) tvId = tvs.length ? tvs[0].id : null;
      var sel = $("tvSelect");
      sel.innerHTML = "";
      tvs.forEach(function (d) { var o = document.createElement("option"); o.value = d.id; o.textContent = d.name; sel.appendChild(o); });
      if (tvId) sel.value = tvId;
      render();
      var cur = state && state.track_id;
      if (cur !== lastTrack) { lastTrack = cur; renderList(); }
    }).catch(function (e) { if (e.message !== "unauthorized") $("err").textContent = "Sin conexión con Sonero."; });
  }

  var timer = null;
  function start() {
    show("remote");
    api("/tv/library").then(function (j) { tracks = j.tracks; renderList(); });
    poll();
    clearInterval(timer);
    timer = setInterval(poll, 1500);
  }

  if (token) start(); else show("pair");
})();
</script>
</body>
</html>
"""
