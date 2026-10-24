/// Self-contained admin page served at `GET /admin`. All data is inserted
/// with textContent (no HTML from the server is interpreted) and the
/// session token lives only in page memory.
const adminPageHtml = r'''<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tactical Mesh – správa</title>
<style>
  :root { color-scheme: dark; --bg:#11140e; --panel:#1b2117; --sand:#c2b280; --red:#e2504c; --green:#4b5320; }
  body { margin:0; font:15px/1.4 system-ui, sans-serif; background:var(--bg); color:#eee; }
  header { padding:12px 16px; background:#171b13; display:flex; gap:12px; align-items:center; }
  header h1 { font-size:18px; margin:0; flex:1; }
  main { padding:16px; max-width:1100px; margin:auto; }
  section { background:var(--panel); border-radius:8px; padding:12px 16px; margin-bottom:16px; }
  h2 { font-size:16px; color:var(--sand); margin:4px 0 12px; }
  input, select, button { font:inherit; padding:6px 8px; border-radius:6px; border:1px solid #555; background:#0d100a; color:#eee; }
  button { background:var(--green); border-color:var(--green); cursor:pointer; }
  button.danger { background:var(--red); border-color:var(--red); }
  button.plain { background:transparent; }
  table { width:100%; border-collapse:collapse; }
  td, th { text-align:left; padding:6px; border-top:1px solid #333; vertical-align:top; }
  .muted { color:#999; font-size:13px; }
  .row { display:flex; flex-wrap:wrap; gap:8px; align-items:center; }
  .error { color:var(--red); min-height:1.4em; }
  .groups label { margin-right:8px; white-space:nowrap; }
  pre { white-space:pre-wrap; font-size:12px; margin:0; }
  [hidden] { display:none !important; }
</style>
</head>
<body>
<header><h1>Tactical Mesh – správa týmů</h1><span id="who" class="muted"></span>
<button id="logout" class="plain" hidden>Odhlásit</button></header>
<main>
  <section id="login-section">
    <h2>Přihlášení velitele</h2>
    <form id="login" class="row">
      <input id="login-user" autocomplete="username" placeholder="uživatel" required>
      <input id="login-pass" type="password" autocomplete="current-password" placeholder="heslo" required>
      <button>Přihlásit</button>
    </form>
    <div id="login-error" class="error"></div>
  </section>

  <div id="app" hidden>
    <section>
      <h2>Uživatelé</h2>
      <div id="users-error" class="error"></div>
      <table><thead><tr><th>Uživatel</th><th>Jméno / role</th><th>Skupiny</th><th>Zařízení</th><th></th></tr></thead>
      <tbody id="users"></tbody></table>
    </section>

    <section>
      <h2>Nový uživatel</h2>
      <form id="create" class="row">
        <input id="new-user" placeholder="uživatel (a-z0-9._-)" required>
        <input id="new-name" placeholder="zobrazované jméno">
        <select id="new-role"></select>
        <span id="new-groups" class="groups"></span>
        <input id="new-pass" type="password" autocomplete="new-password" placeholder="heslo (min. 10 znaků)" required>
        <button>Vytvořit</button>
      </form>
      <div id="create-error" class="error"></div>
    </section>

    <section>
      <h2>Klíče skupin</h2>
      <p class="muted">Rotace vytvoří nový E2EE klíč; připojení klienti ho dostanou při dalším připojení ke skupině (předchozí klíč zůstává platný pro přechod).</p>
      <div id="keys" class="row"></div>
      <div id="keys-error" class="error"></div>
    </section>

    <section>
      <h2>Audit</h2>
      <button id="audit-refresh" class="plain">Obnovit</button>
      <pre id="audit"></pre>
    </section>
  </div>
</main>
<script>
(() => {
  const base = location.pathname.replace(/admin\/?$/, '');
  let token = null;
  let meta = { groups: [], roles: [] };
  const $ = (id) => document.getElementById(id);
  const el = (tag, props = {}, ...children) => {
    const node = document.createElement(tag);
    Object.assign(node, props);
    for (const child of children) node.append(child);
    return node;
  };

  async function api(method, path, body) {
    const response = await fetch(base + path, {
      method,
      headers: Object.assign({ 'content-type': 'application/json' },
        token ? { authorization: 'Bearer ' + token } : {}),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const data = await response.json().catch(() => ({}));
    if (response.status === 401) { logout(); }
    if (!response.ok) throw new Error(data.error || ('HTTP ' + response.status));
    return data;
  }

  function logout() {
    token = null;
    $('app').hidden = true;
    $('login-section').hidden = false;
    $('logout').hidden = true;
    $('who').textContent = '';
  }

  $('logout').onclick = logout;

  $('login').onsubmit = async (event) => {
    event.preventDefault();
    $('login-error').textContent = '';
    try {
      const data = await api('POST', 'auth/login', {
        userName: $('login-user').value, password: $('login-pass').value,
      });
      if (data.user.role !== 'commander') throw new Error('commander_only');
      token = data.sessionToken;
      $('login-pass').value = '';
      $('who').textContent = data.user.displayName;
      $('login-section').hidden = true;
      $('app').hidden = false;
      $('logout').hidden = false;
      await refresh();
    } catch (error) {
      $('login-error').textContent = 'Přihlášení selhalo: ' + error.message;
    }
  };

  function groupBoxes(selected, prefix) {
    const span = el('span', { className: 'groups' });
    for (const group of meta.groups) {
      const box = el('input', { type: 'checkbox', value: group, checked: selected.includes(group) });
      box.dataset.group = prefix;
      span.append(el('label', {}, box, ' ' + group));
    }
    return span;
  }

  function checkedGroups(container) {
    return [...container.querySelectorAll('input[type=checkbox][value]')]
      .filter((box) => box.checked).map((box) => box.value);
  }

  function roleSelect(value) {
    const select = el('select');
    for (const role of meta.roles) select.append(el('option', { value: role, textContent: role, selected: role === value }));
    return select;
  }

  async function refresh() {
    $('users-error').textContent = '';
    try {
      const data = await api('GET', 'admin/users');
      meta = { groups: data.groups, roles: data.roles };
      renderUsers(data.users);
      renderCreateForm();
      renderKeys();
      await refreshAudit();
    } catch (error) {
      $('users-error').textContent = error.message;
    }
  }

  function renderUsers(users) {
    const body = $('users');
    body.replaceChildren();
    for (const user of users) {
      const name = el('input', { value: user.displayName });
      const role = roleSelect(user.role);
      const groups = groupBoxes(user.groups, user.userName);
      const disabled = el('input', { type: 'checkbox', checked: user.disabled });
      const devices = el('div');
      for (const device of user.devices) {
        const unbind = el('button', { className: 'plain', textContent: 'odpojit' });
        unbind.onclick = () => act(() => api('DELETE',
          'admin/users/' + encodeURIComponent(user.userName) + '/devices/' + encodeURIComponent(device.id)));
        devices.append(el('div', { className: 'muted' },
          (device.name || device.id.slice(0, 8)) + ' · ' + device.lastSeen.slice(0, 16).replace('T', ' ') + ' ', unbind));
      }
      const save = el('button', { textContent: 'Uložit' });
      save.onclick = () => act(() => api('PATCH', 'admin/users/' + encodeURIComponent(user.userName), {
        displayName: name.value, role: role.value, groups: checkedGroups(groups), disabled: disabled.checked,
      }));
      const reset = el('button', { className: 'plain', textContent: 'Nové heslo' });
      reset.onclick = () => {
        const password = prompt('Nové heslo pro ' + user.userName + ' (min. 10 znaků):');
        if (password) act(() => api('POST', 'admin/users/' + encodeURIComponent(user.userName) + '/password', { password }));
      };
      const revoke = el('button', { className: 'danger', textContent: 'Odhlásit všude' });
      revoke.onclick = () => act(() => api('POST', 'admin/users/' + encodeURIComponent(user.userName) + '/revoke'));
      body.append(el('tr', {},
        el('td', {}, el('strong', { textContent: user.userName }),
          el('div', { className: 'muted' }, el('label', {}, disabled, ' zablokován'))),
        el('td', {}, el('div', { className: 'row' }, name, role)),
        el('td', {}, groups),
        el('td', {}, devices),
        el('td', {}, el('div', { className: 'row' }, save, reset, revoke)),
      ));
    }
  }

  function renderCreateForm() {
    const role = $('new-role');
    role.replaceChildren(...meta.roles.map((r) => el('option', { value: r, textContent: r })));
    $('new-groups').replaceChildren(...groupBoxes([], 'new').childNodes);
  }

  function renderKeys() {
    const keys = $('keys');
    keys.replaceChildren();
    for (const group of meta.groups) {
      const button = el('button', { className: 'plain', textContent: 'Rotovat klíč ' + group });
      button.onclick = async () => {
        $('keys-error').textContent = '';
        if (!confirm('Rotovat E2EE klíč skupiny ' + group + '?')) return;
        try {
          const data = await api('POST', 'admin/groups/' + encodeURIComponent(group) + '/rotate-key');
          $('keys-error').textContent = 'Skupina ' + group + ': klíč #' + data.keyId;
        } catch (error) { $('keys-error').textContent = error.message; }
      };
      keys.append(button);
    }
  }

  async function refreshAudit() {
    const data = await api('GET', 'admin/audit?limit=100');
    $('audit').textContent = data.entries.map((entry) => {
      const { at, event, user, ...rest } = entry;
      return at.slice(0, 19).replace('T', ' ') + '  ' + event + '  ' + (user || '-') +
        (Object.keys(rest).length ? '  ' + JSON.stringify(rest) : '');
    }).join('\n');
  }

  $('audit-refresh').onclick = () => refreshAudit().catch((e) => { $('audit').textContent = e.message; });

  $('create').onsubmit = async (event) => {
    event.preventDefault();
    $('create-error').textContent = '';
    try {
      await api('POST', 'admin/users', {
        userName: $('new-user').value, displayName: $('new-name').value, role: $('new-role').value,
        groups: checkedGroups($('new-groups')), password: $('new-pass').value,
      });
      $('create').reset();
      await refresh();
    } catch (error) {
      $('create-error').textContent = 'Nelze vytvořit: ' + error.message;
    }
  };

  async function act(action) {
    $('users-error').textContent = '';
    try { await action(); await refresh(); }
    catch (error) { $('users-error').textContent = error.message; }
  }
})();
</script>
</body>
</html>
''';
