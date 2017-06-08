#    HttpKit - An efficient HTTP tool suite written in pure nim
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import httpkit, asyncnet, asyncdispatch

proc processClient(client: AsyncSocket) {.async.} =
  var parser = initRequestParser()
  var reqBuf = newString(1024)
  var resBuf = initResponseBuffer()
  GC_ref(reqBuf)
  block parsing:
    while true:
      reqBuf.setLen(0)
      let n = await client.recvInto(reqBuf.cstring, 1024)
      if n == 0:
        client.close()
        break parsing
      for state in parser.parse(reqBuf.cstring, n):
        case state
        of statReqHead:
          discard
        of statReqData:
          let (base, size) = parser.getData()
        of statReqDataChunked:
          discard
        of statReqDataEnd:
          resBuf.writeHead(200, {
            "Content-Length": "11",
            "Connection": "keep-alive"
          })
          resBuf.write("hello world")
          await client.send(resBuf)
          resBuf.clear()
          if not parser.keepAlive:
            client.close()
            break parsing
          # keep-alive or close return 
        of statReqExpect100Continue:
          await client.send("HTTP/1.1 100 Continue\c\L\c\L")
        of statReqExceptOther:
          await client.send("HTTP/1.1 417 Expectation Failed\c\L\c\L")
        of statReqUpgrade:
          client.close()
          break parsing
        of statReqError:
          client.close()
          break parsing
  GC_unref(reqBuf)

proc serve() {.async.} =
  var server = newAsyncSocket(buffered = false)
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(12345))
  server.listen()
  while true:
    let client = await server.accept()
    asyncCheck client.processClient()

asyncCheck serve()
runForever()


  