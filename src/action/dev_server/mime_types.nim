import tables

const mime_types* = {
  ".html": "text/html",
  ".htm": "text/html",
  ".json": "application/json",
  ".gif": "image/gif",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".pdf": "application/pdf",
  ".md": "text/markdown",
  ".heic": "image/heic",
  ".webp": "image/webp",
  ".css": "text/css",
  ".yaml": "text/yaml",
  ".cson": "application/cson",
  ".mustache": "text/html",
  ".js": "application/javascript",
  ".txt": "text/plain",
}.toTable

proc get_or_default*(extention: string): string =
  result = mime_types.get_or_default(extention, "application/octet-stream")
