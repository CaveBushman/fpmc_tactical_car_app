class NoStoreMiddleware:
    """Nothing this server sends may be cached (tokens, keys, admin data)."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        response["Cache-Control"] = "no-store"
        return response


class PanelSecurityMiddleware:
    """The panel uses no scripts and no external resources: forbid both."""

    POLICY = (
        "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; "
        "form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    )

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if request.path.startswith("/panel/"):
            response["Content-Security-Policy"] = self.POLICY
        return response
