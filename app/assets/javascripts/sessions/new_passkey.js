// Passkey LOGIN ceremony (WebAuthn / navigator.credentials.get) — FedRAMP IA-2.
// Extracted verbatim from app/views/devise/sessions/new.html.haml so the sign-in page
// carries no inline <script> (CSP-reduction step, roadmap unit 5). The base64url<->ArrayBuffer
// encoding and the exact WebAuthn field mapping are browser+authenticator+server-verified and
// MUST NOT drift. Route paths arrive via data-* on #passkey-login-area (not interpolated).
// Loads app-wide via application.js; the PublicKeyCredential + #passkey-login guards below
// make it a no-op on every page except the Devise sign-in page.
(function () {
  if (!window.PublicKeyCredential) { return; }
  var area = document.getElementById('passkey-login-area');
  if (area) { area.style.display = 'block'; }

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
  function setStatus(msg) {
    var el = document.getElementById('passkey-login-status');
    if (!el) { return; }
    el.textContent = msg || '';
    el.style.display = msg ? 'block' : 'none';
  }

  var btn = document.getElementById('passkey-login');
  if (!btn) { return; }
  var optionsUrl = area ? area.getAttribute('data-options-url') : null;
  var callbackUrl = area ? area.getAttribute('data-callback-url') : null;
  btn.addEventListener('click', function () {
    setStatus('');
    var emailField = document.querySelector('input[name="user[email]"]');
    var email = emailField ? emailField.value : '';
    postJSON(optionsUrl, { email: email }).then(function (r) {
      return r.json();
    }).then(function (options) {
      options.challenge = b64uToBuf(options.challenge);
      (options.allowCredentials || []).forEach(function (c) { c.id = b64uToBuf(c.id); });
      return navigator.credentials.get({ publicKey: options });
    }).then(function (cred) {
      var resp = cred.response;
      var payload = {
        credential: {
          id: cred.id,
          rawId: bufToB64u(cred.rawId),
          type: cred.type,
          response: {
            clientDataJSON: bufToB64u(resp.clientDataJSON),
            authenticatorData: bufToB64u(resp.authenticatorData),
            signature: bufToB64u(resp.signature),
            userHandle: resp.userHandle ? bufToB64u(resp.userHandle) : null
          }
        }
      };
      return postJSON(callbackUrl, payload);
    }).then(function (r) {
      return r.json().then(function (j) { return { ok: r.ok, body: j }; });
    }).then(function (res) {
      if (res.ok && res.body.redirect) { window.location = res.body.redirect; }
      else { setStatus(res.body.error || 'Passkey sign-in failed.'); }
    }).catch(function (e) {
      setStatus((e && e.message) || 'Passkey sign-in was cancelled.');
    });
  });
})();
