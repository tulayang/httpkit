#    HttpKit - An efficient HTTP tool suite written in pure nim
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import unittest, httpkit, asyncdispatch, asyncnet

suite "HttpBuffer":
  test "write a string":
    var buf = initResponseBuffer(32)  
    buf.write("abc")
    check buf.len == 3
    buf.clear()
    check buf.len == 0

  test "write a chunk":
    var buf = initResponseBuffer(32)  
    buf.writeChunk("hello")
    #buf.writeChunkTail()
    var base: string
    shallowCopyBase(buf, base)
    check base[0..9] == "5\c\Lhello\c\L"

  test "write a chunk tail":
    var buf = initResponseBuffer(32)  
    buf.writeChunkTail()
    var base: string
    shallowCopyBase(buf, base)
    check base[0..4] == "0\c\L\c\L"

  test "write a head":  
    var buf = initResponseBuffer(32)  
    buf.writeHead(200, {
      "Except": "100-continue"
    })
    var base: string
    shallowCopyBase(buf, base)
    base.setLen(buf.len)
    check base == "HTTP/1.1 200 OK\c\L" &
                  "Except: 100-continue\c\L" &
                  "\c\L"
    