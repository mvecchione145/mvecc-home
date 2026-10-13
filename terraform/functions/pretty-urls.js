// Runs at the edge on every request, before CloudFront looks in S3.
//   /blog/  -> /blog/index.html
//   /blog   -> 301 to /blog/
//   /style.css and other paths with an extension pass through untouched.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
    return request;
  }

  var last = uri.substring(uri.lastIndexOf('/') + 1);
  if (last.indexOf('.') === -1) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: uri + '/' } },
    };
  }

  return request;
}
