import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = (
    "/volume_4/research/seongbong/align/"
    "cerebellum_align_verified2/"
)

PORT = 8002


class NeuroglancerHandler(SimpleHTTPRequestHandler):

    def __init__(self, *args, **kwargs):
        super().__init__(
            *args,
            directory=ROOT,
            **kwargs
        )

    def translate_path(self, path):
        filepath = super().translate_path(path)

        self.serve_gzip = False

        # 요청 파일이 없고 .gz 파일이 있으면 대신 제공
        if (
            not os.path.exists(filepath)
            and os.path.isfile(filepath + ".gz")
            and "gzip" in self.headers.get("Accept-Encoding", "").lower()
        ):
            filepath += ".gz"
            self.serve_gzip = True

        return filepath

    def guess_type(self, path):
        if getattr(self, "serve_gzip", False):
            return "application/octet-stream"
        return super().guess_type(path)

    def end_headers(self):

        if getattr(self, "serve_gzip", False):
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Vary", "Accept-Encoding")

        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header(
            "Access-Control-Allow-Methods",
            "GET, HEAD, OPTIONS"
        )
        self.send_header(
            "Access-Control-Allow-Headers",
            "Range, Content-Type"
        )

        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()


server = ThreadingHTTPServer(
    ("127.0.0.1", PORT),
    NeuroglancerHandler
)

print(f"Serving {ROOT}")
print(f"Port: {PORT}")

server.serve_forever()
