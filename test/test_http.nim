#    HttpKit - An efficient HTTP tool suite written in pure nim
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import unittest, httpkit, asyncdispatch, asyncnet

suite "HttpParser":
  test "construct a base HTTP server and client":
    var clients = 0

    proc processClient(client: AsyncSocket) {.async.} =
      var parser = initRequestParser()
      var reqBuf = newString(1024)
      var resBuf = initResponseBuffer()
      var data = newString(1024)
      var dataPos = 0
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
              let (offset, size) = parser.getData()
              copyMem(cast[pointer](cast[ByteAddress](data.cstring) + dataPos), 
                      cast[pointer](cast[ByteAddress](reqBuf.cstring) + offset),
                      size)
              inc(dataPos, size)
            of statReqDataChunked:
              discard
            of statReqDataEnd:
              data.setLen(dataPos)
              check data == "Hello server"
              echo "  >>> Server got '", data, "'"
              resBuf.writeHead(200, {
                "Content-Length": "12",
                "Connection": "keep-alive"
              })
              resBuf.write("Hello client")
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

    proc consServer() {.async.} =
      var server = newAsyncSocket(buffered = false)
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(Port(12345))
      server.listen()
      while true:
        let client = await server.accept()
        clients.inc(1)
        client.processClient().callback = proc () =
          clients.dec(1)
          if clients == 0:
            clients = -1
            server.close()

    proc processConnect(client: AsyncSocket) {.async.} =
      var parser = initResponseParser()
      var resBuf = newString(1024)
      var reqBuf = initRequestBuffer()
      var data = newString(1024)
      var dataPos = 0
      reqBuf.writeHead("GET", "/", {
        "Content-Length": "12",
        "Connection": "keep-alive"
      })
      reqBuf.write("Hello server")
      await client.send(reqBuf)
      reqBuf.clear()
      GC_ref(resBuf)
      block parsing:
        while true:
          resBuf.setLen(0)
          let n = await client.recvInto(resBuf.cstring, 1024)
          if n == 0:
            client.close()
            break parsing
          for state in parser.parse(resBuf.cstring, n):
            case state
            of statResHead:
              discard
            of statResData:
              let (offset, size) = parser.getData()
              copyMem(cast[pointer](cast[ByteAddress](data.cstring) + dataPos), 
                      cast[pointer](cast[ByteAddress](resBuf.cstring) + offset),
                      size)
              inc(dataPos, size)
            of statResDataChunked:
              discard
            of statResDataEnd:
              data.setLen(dataPos)
              check data == "Hello client"
              echo "  >>> Client got '", data, "'"
              if parser.keepAlive:
                discard
              client.close()
              break parsing
            of statResUpgrade:
              client.close()
              break parsing
            of statResError:
              client.close()
              break parsing
      GC_unref(resBuf)

    proc consClient() {.async.} =
      var client = newAsyncSocket(buffered = false)
      await client.connect("127.0.0.1", Port(12345))
      await client.processConnect()

    asyncCheck consServer()
    asyncCheck consClient()
    while true:
      poll()
      if clients == -1:
        break
