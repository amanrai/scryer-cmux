export function corsHeaders(extra = {}) {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'access-control-allow-headers': 'content-type,x-smux-filename',
    ...extra,
  };
}

export function json(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json', ...corsHeaders() });
  res.end(JSON.stringify(payload));
}

export function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}
