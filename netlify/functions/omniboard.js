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
    // только безопасные для повтора запросы (GET/HEAD) и только при сетевом
    // сбое: ответ с кодом ошибки отдаём как есть, его повторит клиент.
    const isRetryable = ['GET', 'HEAD'].includes(event.httpMethod);
    const attempts = isRetryable ? 3 : 1;

    let response;
    let lastError;
    for (let attempt = 0; attempt < attempts; attempt++) {
      try {
        response = await fetch(url, {method: event.httpMethod, headers, body});
        lastError = undefined;
        break;
      } catch (error) {
        lastError = error;
        if (attempt < attempts - 1) {
          await new Promise((resolve) => setTimeout(resolve, 300 * (attempt + 1)));
        }
      }
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
