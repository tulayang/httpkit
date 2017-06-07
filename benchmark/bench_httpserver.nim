import httpkit, asyncnet, asyncdispatch

proc processClient(client: AsyncSocket) {.async.} =
  var parser = initHttpParser()
  var reqBuf = newString(1024)
  var resBuf = initHttpBuffer()
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
        of psRequest:
          discard
        of psData:
          let (base, size) = parser.getData()
        of psDataChunked:
          discard
        of psDataEnd:
          resBuf.writeHead(200, {
            "Content-Length": "11",
            "Connection": "keep-alive"
          })
          resBuf.write("hello world")
          # resBuf.writeChunk("hello world")
          # await client.send(resBuf)
          # resBuf.clear()

          # resBuf.writeChunk("hello world")
          # resBuf.writeChunkTail()
          await client.send(resBuf)
          resBuf.clear()
          if not parser.keepAlive:
            client.close()
            break parsing
          # keep-alive or close return 
        of psExpect100Continue:
          await client.send("HTTP/1.1 100 Continue\c\L\c\L")
        of psExceptOther:
          await client.send("HTTP/1.1 417 Expectation Failed\c\L\c\L")
        of psUpgrade:
          client.close()
          break parsing
        of psError:
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


  