const UPSTREAM_ORIGIN = 'https://proddsp.omniboard360.io';
const FUNCTION_PREFIX = '/.netlify/functions/omniboard';

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
      },
    };
  }

  try {
    const upstreamPath = event.path.startsWith(FUNCTION_PREFIX)
        ? event.path.substring(FUNCTION_PREFIX.length)
        : event.path;
    const normalizedPath = upstreamPath.startsWith('/')
        ? upstreamPath
        : `/${upstreamPath}`;
    const rawQuery = event.rawQuery ? `?${event.rawQuery}` : '';
    const url = `${UPSTREAM_ORIGIN}${normalizedPath}${rawQuery}`;

    const headers = {};
    for (const [key, value] of Object.entries(event.headers || {})) {
      const lowerKey = key.toLowerCase();
      if (['host', 'x-forwarded-for', 'x-nf-account-id', 'x-nf-request-id'].includes(lowerKey)) {
        continue;
      }
      headers[key] = value;
    }

    const body = ['GET', 'HEAD'].includes(event.httpMethod)
        ? undefined
        : event.isBase64Encoded
            ? Buffer.from(event.body || '', 'base64')
            : event.body;

    // Бэкенд иногда обрывает соединение на одном запросе из пачки, и тогда
    // fetch падает ещё до ответа — клиент видел 502 «fetch failed». Повторяем
    // только безопасные для повтора запросы (GET/HEAD).
    //
    // Повторяем и ответы 502/503/504 от самого бэкенда: раньше они уходили
    // клиенту как есть, и повтор шёл вторым кругом через CDN — то есть на
    // каждую попытку тратился лишний путь туда-обратно. Здесь мы уже рядом с
    // бэкендом, так что повтор дешевле и быстрее.
    const isRetryable = ['GET', 'HEAD'].includes(event.httpMethod);
    const backoffMs = isRetryable ? [400, 1200, 2500] : [];

    let response;
    let lastError;
    for (let attempt = 0; attempt <= backoffMs.length; attempt++) {
      try {
        response = await fetch(url, {method: event.httpMethod, headers, body});
        lastError = undefined;
        const upstreamGlitch = [502, 503, 504].includes(response.status);
        if (!upstreamGlitch || attempt === backoffMs.length) {
          break;
        }
      } catch (error) {
        lastError = error;
        if (attempt === backoffMs.length) {
          break;
        }
      }
      await new Promise((resolve) => setTimeout(resolve, backoffMs[attempt]));
    }
    if (lastError !== undefined) {
      throw lastError;
    }

    const contentType = response.headers.get('content-type');
    const responseBody = await response.arrayBuffer();
    const bodyBuffer = Buffer.from(responseBody);
    const isBinary = contentType != null &&
        !contentType.includes('application/json') &&
        !contentType.startsWith('text/') &&
        !contentType.includes('javascript');

    return {
      statusCode: response.status,
      isBase64Encoded: isBinary,
      headers: {
        'Access-Control-Allow-Origin': '*',
        ...(contentType == null ? {} : {'content-type': contentType}),
      },
      body: isBinary ? bodyBuffer.toString('base64') : bodyBuffer.toString('utf8'),
    };
  } catch (error) {
    return {
      statusCode: 502,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        error: 'Proxy request failed',
        message: error instanceof Error ? error.message : String(error),
      }),
    };
  }
};
