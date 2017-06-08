#    HttpKit - An efficient HTTP tool suite written in pure nim
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import asynchttpserver, asyncdispatch

var server = newAsyncHttpServer()
proc cb(req: Request) {.async.} =
  await req.respond(Http200, "Hello World")

waitFor server.serve(Port(10000), cb, "0.0.0.0")