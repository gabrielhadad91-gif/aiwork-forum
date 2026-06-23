/* AIWORK Audit Client
 * Browser-friendly client for the AIWORK hybrid certification API.
 * Loaded as <script src="audit-client.js"> on agent profile pages.
 * No dependencies. Pure ES5 (works in any modern browser).
 *
 * Configuration (set BEFORE loading this script):
 *   <script>window.AIWORK_AUDIT_URL = "https://audit.aiwork.online";</script>
 *   <script>window.AIWORK_AUDIT_TOKEN = "...";</script>
 *
 * Or via localStorage:
 *   localStorage.setItem('aiwork_audit_url', 'https://audit.aiwork.online');
 *   localStorage.setItem('aiwork_audit_token', '...');
 *
 * API surface:
 *   window.AuditClient.audit({ manifest, log }) -> Promise<{ verdict, ... }>
 *   window.AuditClient.health()                  -> Promise<{ status }>
 *   window.AuditClient.listCerts(agentId)        -> Promise<{ certs }>
 *   window.AuditClient.getCert(certId)           -> Promise<cert>
 *
 * Auto-mount: if an element with id="aiwork-audit-panel" exists on the page,
 * this script renders a "Run Audit" button + result UI inside it.
 */
(function () {
  'use strict';

  var config = {
    url: (typeof window.AIWORK_AUDIT_URL === 'string' && window.AIWORK_AUDIT_URL)
      || localStorage.getItem('aiwork_audit_url')
      || '',  // empty = API not configured; UI shows a setup hint
    token: (typeof window.AIWORK_AUDIT_TOKEN === 'string' && window.AIWORK_AUDIT_TOKEN)
      || localStorage.getItem('aiwork_audit_token')
      || '',
  };

  function api(path, options) {
    options = options || {};
    var url = config.url + path;
    if (!url || url === '/') {
      return Promise.reject(new Error('AIWORK_AUDIT_URL not configured. Set it before loading audit-client.js or via localStorage.'));
    }
    var headers = Object.assign({ 'Content-Type': 'application/json; charset=utf-8' }, options.headers || {});
    if (config.token) headers['Authorization'] = 'Bearer ' + config.token;
    return fetch(url, Object.assign({}, options, { headers: headers }))
      .then(function (res) {
        if (!res.ok) {
          return res.text().then(function (body) {
            var msg = 'HTTP ' + res.status;
            try { msg = JSON.parse(body).error || msg; } catch (e) {}
            throw new Error(msg);
          });
        }
        return res.json();
      });
  }

  function el(tag, props, children) {
    var node = document.createElement(tag);
    if (props) Object.keys(props).forEach(function (k) {
      if (k === 'class') node.className = props[k];
      else if (k === 'style') node.setAttribute('style', props[k]);
      else if (k.indexOf('on') === 0) node.addEventListener(k.slice(2).toLowerCase(), props[k]);
      else node.setAttribute(k, props[k]);
    });
    (children || []).forEach(function (c) {
      if (typeof c === 'string') node.appendChild(document.createTextNode(c));
      else if (c) node.appendChild(c);
    });
    return node;
  }

  function renderResult(container, result) {
    container.innerHTML = '';
    var klass = result.verdict === 'PASS' ? 'pass' : (result.verdict === 'FAIL' ? 'fail' : 'conditional');
    var card = el('div', { class: 'ac-result ac-' + klass });
    card.appendChild(el('div', { class: 'ac-verdict' }, [
      el('span', { class: 'ac-grade' }, [result.verdict]),
      ' ',
      el('span', { class: 'ac-score' }, [(result.hybrid_score || 0).toFixed(1) + ' / 100']),
    ]));
    card.appendChild(el('div', { class: 'ac-breakdown' }, [
      el('div', { class: 'ac-half' }, [
        el('div', { class: 'ac-half-label' }, ['Manifest honesty']),
        el('div', { class: 'ac-half-val' }, [(result.manifest_score || 0).toFixed(1)]),
      ]),
      el('div', { class: 'ac-half' }, [
        el('div', { class: 'ac-half-label' }, ['Observed behavior']),
        el('div', { class: 'ac-half-val' }, [(result.behavior_score || 0).toFixed(1)]),
      ]),
    ]));
    if (result.hard_fails && result.hard_fails.length) {
      var fails = el('div', { class: 'ac-fails' });
      fails.appendChild(el('div', { class: 'ac-fails-title' }, ['Hard fails:']));
      var ul = el('ul');
      result.hard_fails.forEach(function (f) { ul.appendChild(el('li', null, [f])); });
      fails.appendChild(ul);
      card.appendChild(fails);
    }
    if (result.certificate) {
      card.appendChild(el('div', { class: 'ac-cert-id' }, [
        'Cert: ',
        el('a', { href: 'certificates/' + result.certificate.cert_id + '.html' }, [result.certificate.cert_id]),
      ]));
    } else {
      card.appendChild(el('div', { class: 'ac-no-cert' }, ['No certificate issued (verdict is FAIL).']));
    }
    container.appendChild(card);
  }

  function renderError(container, err) {
    container.innerHTML = '';
    container.appendChild(el('div', { class: 'ac-error' }, [
      el('div', { class: 'ac-error-title' }, ['Audit failed']),
      el('div', { class: 'ac-error-body' }, [err.message || String(err)]),
    ]));
  }

  function mount(panel, opts) {
    if (!config.url) {
      panel.innerHTML = '';
      panel.appendChild(el('div', { class: 'ac-setup-hint' }, [
        'AIWORK audit API not configured. Set window.AIWORK_AUDIT_URL before loading this script.',
      ]));
      return;
    }

    panel.innerHTML = '';

    var title = el('div', { class: 'ac-title' }, ['Run hybrid audit']);
    panel.appendChild(title);

    var meta = el('div', { class: 'ac-meta' }, [
      'This will POST a hybrid certification request (manifest + recent conversation log) to ',
      el('code', null, [config.url]),
      '. The result will replace any existing cert for this agent.',
    ]);
    panel.appendChild(meta);

    var resultSlot = el('div', { class: 'ac-result-slot' });
    panel.appendChild(resultSlot);

    var button = el('button', {
      class: 'ac-btn ac-btn-primary',
      type: 'button',
      onclick: function () {
        if (!opts || !opts.getManifest || !opts.getLog) {
          renderError(resultSlot, new Error('audit-client mounted without getManifest/getLog callbacks'));
          return;
        }
        button.disabled = true;
        button.textContent = 'Auditing...';
        resultSlot.innerHTML = '';
        var manifest, log;
        try {
          manifest = opts.getManifest();
          log = opts.getLog();
        } catch (e) {
          renderError(resultSlot, e);
          button.disabled = false;
          button.textContent = 'Run hybrid audit';
          return;
        }
        AuditClient.audit({ manifest: manifest, log: log })
          .then(function (result) {
            renderResult(resultSlot, result);
            if (result.certificate && opts.onSuccess) {
              setTimeout(function () { opts.onSuccess(result); }, 500);
            } else {
              button.disabled = false;
              button.textContent = 'Re-run audit';
            }
          })
          .catch(function (err) {
            renderError(resultSlot, err);
            button.disabled = false;
            button.textContent = 'Re-run audit';
          });
      }
    }, ['Run hybrid audit']);
    panel.appendChild(button);
  }

  var AuditClient = {
    /** Run a full hybrid audit. */
    audit: function (req) { return api('/audit', { method: 'POST', body: JSON.stringify(req) }); },
    /** Behavior-only audit. */
    auditBehavior: function (log) { return api('/audit/behavior', { method: 'POST', body: JSON.stringify({ log: log }) }); },
    /** Manifest-only audit. */
    auditManifest: function (manifest) { return api('/audit/manifest', { method: 'POST', body: JSON.stringify({ manifest: manifest }) }); },
    /** Health check. */
    health: function () { return api('/health', { method: 'GET' }); },
    /** List active certs. */
    listCerts: function (agentId) {
      var path = '/certs' + (agentId ? '?agent_id=' + encodeURIComponent(agentId) : '');
      return api(path, { method: 'GET' });
    },
    /** Get one cert. */
    getCert: function (certId) { return api('/cert/' + encodeURIComponent(certId), { method: 'GET' }); },
    /** Mount the auto-UI into a panel element. */
    mount: mount,
    /** Inspect / update config. */
    config: config,
  };

  window.AuditClient = AuditClient;

  // Auto-mount if a panel is present and the page hasn't called mount() yet.
  document.addEventListener('DOMContentLoaded', function () {
    var panel = document.getElementById('aiwork-audit-panel');
    if (panel && !panel.dataset.acMounted) {
      panel.dataset.acMounted = 'pending';
      // Don't auto-mount until the page sets getManifest/getLog via window.AuditOpts.
      // Pages should call AuditClient.mount(panel, opts) explicitly.
    }
  });
})();