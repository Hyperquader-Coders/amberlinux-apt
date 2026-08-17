// Serves pool/** from R2 (run_worker_first routes only those paths here);
// anything else falls through to the static assets. Pool paths embed the
// package version, so objects are immutable and cache for a year. apt
// needs real status codes and untouched bytes — no path redirects, ever.
// The scheme is the one exception: signatures prove origin, not freshness,
// so plain HTTP lets an on-path attacker stall or replay an older validly
// signed InRelease. HTTP gets a 301 to the same path over TLS, and every
// response carries HSTS.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.protocol === 'http:') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }
    // html_handling "none" (which protects the extension-less apt files)
    // also disables / -> index.html, so the landing page is mapped here.
    if (url.pathname === '/') {
      return env.ASSETS.fetch(new URL('/index.html', url).toString());
    }
    if (!url.pathname.startsWith('/pool/')) {
      return env.ASSETS.fetch(request);
    }
    // On error responses too: HSTS pins on whatever response a client sees
    // first, and a probe of a missing package must not be the exception.
    const hsts = { 'Strict-Transport-Security': 'max-age=31536000' };

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('method not allowed', { status: 405, headers: hsts });
    }
    // apt percent-encodes characters like the + in "2026.08+dev";
    // url.pathname preserves the encoding, R2 keys hold literal bytes.
    let key;
    try {
      key = decodeURIComponent(url.pathname).slice(1);
    } catch {
      return new Response('bad request', { status: 400, headers: hsts });
    }
    const object = await env.POOL.get(key);
    if (object === null) {
      return new Response('not found', { status: 404, headers: hsts });
    }
    const headers = new Headers({
      'Content-Type': 'application/vnd.debian.binary-package',
      'Content-Length': String(object.size),
      'Cache-Control': 'public, max-age=31536000, immutable',
      'ETag': object.httpEtag,
      'Strict-Transport-Security': 'max-age=31536000',
    });
    return new Response(request.method === 'HEAD' ? null : object.body, {
      headers,
    });
  },
};
