name: "Markdown"
version: "0.1.0"
author: "Jonas Schubert Erlandsson"
description: "Load any JSON files found into context"
license: "MIT"

proc for_each_field*( path, content: string ) =
  let html = exe( "echo \"" & content & "\"| commonmark --" )
  ctx_set( path, html )
