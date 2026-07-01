// Passkey REGISTRATION ceremony (WebAuthn / navigator.credentials.create) — FedRAMP IA-2.
// Extracted verbatim from app/views/passkeys/show.html.haml so that page carries no inline
// <script> (CSP-reduction step, roadmap unit 5). base64url<->ArrayBuffer encoding + the exact
// WebAuthn field mapping (attestationObject; user.id/excludeCredentials decode; top-level nickname)
// MUST NOT drift. Route paths arrive via data-* on #passkey-register-area (not interpolated).
//
// PAGE GUARD: the inline original ran unconditionally and would null-deref on any page lacking
// #passkey-unsupported / #passkey-register. This bundle loads app-wide, so we early-return unless
// the passkeys/show markup is present. This changes NOTHING on the passkeys page itself.
(function () {
  var area = document.getElementById('passkey-register-area');
  var unsupported = document.getElementById('passkey-unsupported');
  var registerBtn = document.getElementById('passkey-register');
  if (!area || !unsupported || !registerBtn) { return; }

  if (!window.PublicKeyCredential) {
    unsupported.style.display = 'block';
    if (area) { area.style.display = 'none'; }
    return;
  }
  var optionsUrl = area.getAttribute('data-options-url');
  var passkeysUrl = area.getAttribute('data-passkeys-url');
  // base64url <-> ArrayBuffer (WebAuthn options arrive as base64url; responses must be re-encoded).
  function b64uToBuf(s) {
    s = s.replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) { s += '='; }
    var bin = atob(s), buf = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) { buf[i] = bin.charCodeAt(i); }
    return buf.buffer;
  }
  function bufToB64u(buf) {
    var bytes = new Uint8Array(buf), s = '';
    for (var i = 0; i < bytes.length; i++) { s += String.fromCharCode(bytes[i]); }
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
  function csrf() {
    var m = document.querySelector('meta[name=csrf-token]');
    return m ? m.content : '';
  }
  function postJSON(url, body) {
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'X-CSRF-Token': csrf() },
      body: JSON.stringify(body || {})
    });
  }
  function setStatus(msg, isError) {
    var el = document.getElementById('passkey-register-status');
    el.textContent = msg || '';
    el.className = (isError ? 'text-danger' : 'text-success') + ' m-l';
  }

  registerBtn.addEventListener('click', function () {
    var nickname = document.getElementById('passkey_nickname').value;
    setStatus('Waiting for your device...', false);
    postJSON(optionsUrl, {}).then(function (r) {
      return r.json();
    }).then(function (options) {
      options.challenge = b64uToBuf(options.challenge);
      options.user.id = b64uToBuf(options.user.id);
      (options.excludeCredentials || []).forEach(function (c) { c.id = b64uToBuf(c.id); });
      return navigator.credentials.create({ publicKey: options });
    }).then(function (cred) {
      var payload = {
        nickname: nickname,
        credential: {
          id: cred.id,
          rawId: bufToB64u(cred.rawId),
          type: cred.type,
          response: {
            clientDataJSON: bufToB64u(cred.response.clientDataJSON),
            attestationObject: bufToB64u(cred.response.attestationObject)
          }
        }
      };
      return postJSON(passkeysUrl, payload);
    }).then(function (r) {
      return r.json().then(function (j) { return { ok: r.ok, body: j }; });
    }).then(function (res) {
      if (res.ok) { window.location = passkeysUrl; }
      else { setStatus(res.body.error || 'Registration failed.', true); }
    }).catch(function (e) {
      setStatus((e && e.message) || 'Registration was cancelled.', true);
    });
  });
})();
