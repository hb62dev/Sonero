"""Self-contained upload page served by the WiFi receiver at GET /.

Kept as a Python string (not a static file) so PyInstaller bundles it without
extra spec configuration. No external assets: it must work on a LAN without
internet access.
"""

UPLOAD_PAGE_HTML = """<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0f0f12">
<title>Enviar a Sonero</title>
<style>
  :root {
    --bg: #0f0f12; --surface: #1a1a1f; --surface-alt: #232329; --border: #2e2e36;
    --text: #f4f4f6; --muted: #9a9aa6; --accent: #7c4dff; --ok: #8bc34a; --err: #ff5c6c;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--bg); color: var(--text);
    font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 560px; margin: 0 auto; padding: 24px 16px 48px; }
  header { display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }
  .logo { width: 40px; height: 40px; border-radius: 12px; background: var(--accent);
    display: grid; place-items: center; font-weight: 800; font-size: 20px; color: #fff; }
  h1 { font-size: 18px; margin: 0; }
  .sub { color: var(--muted); font-size: 13px; margin: 2px 0 0; }
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: 16px; padding: 16px; }
  .drop { border: 2px dashed var(--border); border-radius: 14px; padding: 28px 16px; text-align: center;
    cursor: pointer; transition: border-color .15s, background .15s; }
  .drop.over { border-color: var(--accent); background: rgba(124, 77, 255, .08); }
  .drop strong { display: block; margin-bottom: 4px; }
  .drop span { color: var(--muted); font-size: 13px; }
  input[type=file] { display: none; }
  label.field { display: block; margin-top: 14px; font-size: 13px; color: var(--muted); }
  input[type=text] { width: 100%; margin-top: 6px; padding: 11px 12px; border-radius: 10px;
    border: 1px solid var(--border); background: var(--surface-alt); color: var(--text); font-size: 15px; }
  button { width: 100%; margin-top: 16px; padding: 13px; border: 0; border-radius: 12px;
    background: var(--accent); color: #fff; font-size: 15px; font-weight: 600; cursor: pointer; }
  button:disabled { opacity: .45; cursor: default; }
  ul { list-style: none; padding: 0; margin: 16px 0 0; display: grid; gap: 8px; }
  li { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 10px 12px; }
  .name { font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .meta { display: flex; justify-content: space-between; font-size: 12px; color: var(--muted); margin-top: 4px; }
  .bar { height: 4px; border-radius: 4px; background: var(--border); margin-top: 8px; overflow: hidden; }
  .bar > i { display: block; height: 100%; width: 0; background: var(--accent); transition: width .15s; }
  .done .meta b { color: var(--ok); } .failed .meta b { color: var(--err); }
  .done .bar > i { background: var(--ok); } .failed .bar > i { background: var(--err); }
  footer { margin-top: 20px; color: var(--muted); font-size: 12px; text-align: center; }
</style>
</head>
<body>
<main>
  <header>
    <div class="logo">S</div>
    <div>
      <h1>Enviar a Sonero</h1>
      <p class="sub" id="device">Conectando…</p>
    </div>
  </header>

  <div class="card">
    <div class="drop" id="drop" role="button" tabindex="0">
      <strong>Toca para elegir canciones o videos</strong>
      <span>MP3, M4A, FLAC, WAV, OGG, MP4, MKV, MOV…</span>
    </div>
    <input type="file" id="files" multiple
           accept="audio/*,video/*,.mp3,.m4a,.flac,.wav,.ogg,.opus,.aac,.wma,.webm,.mp4,.mkv,.mov">
    <label class="field">Playlist (opcional, solo música)
      <input type="text" id="playlist" list="playlists" placeholder="Sin playlist" autocomplete="off">
      <datalist id="playlists"></datalist>
    </label>
    <button id="send" disabled>Enviar</button>
  </div>

  <ul id="queue"></ul>
  <footer>Mantén esta página abierta hasta que terminen los envíos.</footer>
</main>

<script>
(function () {
  var AUDIO = ["mp3","m4a","opus","ogg","wav","aac","flac","wma","webm"];
  var VIDEO = ["mp4","mkv","mov"];
  var picked = [];
  var busy = false;
  var $ = function (id) { return document.getElementById(id); };

  fetch("/info").then(function (r) { return r.json(); }).then(function (info) {
    $("device").textContent = "Destino: " + info.device;
    (info.playlists || []).forEach(function (name) {
      var o = document.createElement("option"); o.value = name; $("playlists").appendChild(o);
    });
  }).catch(function () { $("device").textContent = "Sonero no responde. ¿Sigue activa la recepción?"; });

  function ext(name) { var i = name.lastIndexOf("."); return i < 0 ? "" : name.slice(i + 1).toLowerCase(); }
  function typeOf(name) {
    var e = ext(name);
    if (VIDEO.indexOf(e) >= 0) return "video";
    if (AUDIO.indexOf(e) >= 0) return "music";
    return null;
  }
  function mb(n) { return (n / 1048576).toFixed(1) + " MB"; }

  function row(file) {
    var li = document.createElement("li");
    li.innerHTML = '<div class="name"></div><div class="meta"><b>En cola</b><span></span></div><div class="bar"><i></i></div>';
    li.querySelector(".name").textContent = file.name;
    li.querySelector(".meta span").textContent = mb(file.size);
    $("queue").appendChild(li);
    return {
      set: function (cls, label, pct) {
        li.className = cls || "";
        li.querySelector(".meta b").textContent = label;
        if (pct != null) li.querySelector(".bar > i").style.width = pct + "%";
      }
    };
  }

  function pick(list) {
    $("queue").innerHTML = "";
    picked = [];
    Array.prototype.forEach.call(list, function (f) {
      var r = row(f);
      if (!typeOf(f.name)) { r.set("failed", "Formato no soportado", 100); return; }
      picked.push({ file: f, ui: r });
    });
    $("send").disabled = picked.length === 0;
    $("send").textContent = picked.length ? "Enviar " + picked.length + " archivo(s)" : "Enviar";
  }

  function upload(item, playlist) {
    var f = item.file, type = typeOf(f.name);
    item.ui.set("", "Preparando…", 0);
    return fetch("/prepare", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ filename: f.name, type: type, size: f.size,
                             playlist: type === "music" ? playlist : null })
    }).then(function (r) {
      if (!r.ok) return r.json().then(function (j) { throw new Error(j.detail || r.statusText); });
      return new Promise(function (resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "/upload?filename=" + encodeURIComponent(f.name));
        xhr.setRequestHeader("Content-Type", "application/octet-stream");
        xhr.upload.onprogress = function (e) {
          if (e.lengthComputable) {
            var p = Math.floor(e.loaded * 100 / e.total);
            item.ui.set("", "Enviando… " + p + "%", p);
          }
        };
        xhr.onload = function () {
          if (xhr.status >= 200 && xhr.status < 300) return resolve();
          var msg = xhr.statusText;
          try { msg = JSON.parse(xhr.responseText).detail || msg; } catch (e) {}
          reject(new Error(msg));
        };
        xhr.onerror = function () { reject(new Error("Conexión perdida")); };
        xhr.send(f);
      });
    }).then(function () {
      item.ui.set("done", "Enviado", 100);
    }).catch(function (e) {
      item.ui.set("failed", "Error: " + e.message, 100);
    });
  }

  $("drop").addEventListener("click", function () { if (!busy) $("files").click(); });
  $("drop").addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") $("files").click(); });
  $("files").addEventListener("change", function (e) { pick(e.target.files); });
  ["dragenter", "dragover"].forEach(function (t) {
    $("drop").addEventListener(t, function (e) { e.preventDefault(); $("drop").classList.add("over"); });
  });
  ["dragleave", "drop"].forEach(function (t) {
    $("drop").addEventListener(t, function (e) { e.preventDefault(); $("drop").classList.remove("over"); });
  });
  $("drop").addEventListener("drop", function (e) { if (!busy) pick(e.dataTransfer.files); });

  $("send").addEventListener("click", function () {
    if (busy || !picked.length) return;
    busy = true;
    $("send").disabled = true;
    var playlist = $("playlist").value.trim() || null;
    var queue = picked.slice();
    picked = [];
    (function next() {
      var item = queue.shift();
      if (!item) {
        busy = false;
        $("files").value = "";
        $("send").textContent = "Enviar";
        return;
      }
      upload(item, playlist).then(next);
    })();
  });
})();
</script>
</body>
</html>
"""
