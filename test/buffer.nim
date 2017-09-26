#    HttpKit - An efficient HTTP parser written in pure nim
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import os, net, asyncnet, asyncdispatch, nativesockets

type
  HttpBuffer* = object of RootObj
    base: string
    pageSize: int
    realSize: int
    baseLen: int
  RequestBuffer* = object of HttpBuffer
  ResponseBuffer* = object of HttpBuffer 

template offsetChar(x: pointer, i: int): pointer =
  cast[pointer](cast[ByteAddress](x) + i * sizeof(char))

proc toChunkrealSize*(x: BiggestInt): string =
  assert x >= 0
  const HexChars = "0123456789ABCDEF"
  var n = x
  var m = 0
  var s = newString(5) # realSizeof(BiggestInt) * 10 / 16
  for j in countdown(4, 0):
    s[j] = HexChars[n and 0xF]
    n = n shr 4
    inc(m)
    if n == 0: 
      break
  result = newStringOfCap(m)
  for i in 5-m..<5:
    add(result, s[i])

template initHttpBufferImpl() {.dirty.} =
  result.pageSize = pageSize
  result.realSize = pageSize
  result.base = newString(pageSize)
  result.baseLen = 0

proc initRequestBuffer*(pageSize = 1024): RequestBuffer =
  initHttpBufferImpl

proc initResponseBuffer*(pageSize = 1024): ResponseBuffer =
  initHttpBufferImpl

proc expandIfNeeded(x: var HttpBuffer, size: int) =
  if size > x.realSize - x.baseLen:
    x.realSize = ((x.baseLen + size) div x.pageSize + 1) * x.pageSize  
    var base: string
    shallowCopy(base, x.base) 
    x.base = newString(x.realSize)
    copyMem(x.base.cstring, base.cstring, x.baseLen)

proc write*(x: var HttpBuffer, buf: pointer, realSize: int) =
  if realSize > x.realSize - x.baseLen:
    x.expandIfNeeded(realSize)
  copyMem(offsetChar(x.base.cstring, x.baseLen), buf, realSize)
  x.baseLen.inc(realSize)

proc write*(x: var HttpBuffer, buf: string) =
  x.write(buf.cstring, buf.len)

proc writeLine*(x: var HttpBuffer, buf: pointer, realSize: int) =
  let totalrealSize = realSize + 2
  if totalrealSize > x.realSize - x.baseLen:
    x.expandIfNeeded(totalrealSize)
  copyMem(offsetChar(x.base.cstring, x.baseLen), buf, realSize)
  x.baseLen.inc(realSize)
  var tail = ['\c', '\L']
  copyMem(offsetChar(x.base.cstring, x.baseLen), tail[0].addr, 2)
  x.baseLen.inc(2)

proc writeLine*(x: var HttpBuffer, buf: string) = 
  x.writeLine(buf.cstring, buf.len)

proc writeChunk*(x: var HttpBuffer, buf: pointer, realSize: int) =
  let chunkrealSize = realSize.toChunkrealSize()
  let chunkrealSizeLen = chunkrealSize.len()
  let totalrealSize = chunkrealSizeLen + 2 + realSize + 2
  if totalrealSize > x.realSize - x.baseLen:
    x.expandIfNeeded(totalrealSize)
  var tail = ['\c', '\L']
  copyMem(offsetChar(x.base.cstring, x.baseLen), chunkrealSize.cstring, chunkrealSizeLen)
  x.baseLen.inc(chunkrealSizeLen)
  copyMem(offsetChar(x.base.cstring, x.baseLen), tail[0].addr, 2)
  x.baseLen.inc(2)
  copyMem(offsetChar(x.base.cstring, x.baseLen), buf, realSize)
  x.baseLen.inc(realSize)
  copyMem(offsetChar(x.base.cstring, x.baseLen), tail[0].addr, 2)
  x.baseLen.inc(2)

proc writeChunk*(x: var HttpBuffer, buf: string) =
  x.writeChunk(buf.cstring, buf.len)

proc writeChunkTail*(x: var HttpBuffer) =
  if 5 > x.realSize - x.baseLen:
    x.expandIfNeeded(5)
  var tail = ['0', '\c', '\L', '\c', '\L']
  copyMem(offsetChar(x.base.cstring, x.baseLen), tail[0].addr, 5)
  x.baseLen.inc(5)

proc writeHead*(x: var ResponseBuffer, statusCode: int) =
  x.write("HTTP/1.1 " & $statusCode & " OK\c\LContent-baseLen: 0\c\L\c\L")

proc writeHead*(x: var ResponseBuffer, statusCode: int, 
                headers: openarray[tuple[key, value: string]]) =
  x.write("HTTP/1.1 " & $statusCode & " OK\c\L")
  for it in headers:
    x.write(it.key & ": " & it.value & "\c\L")
  x.write("\c\L")

proc writeHead*(x: var RequestBuffer, reqMethod: string, url: string) =
  x.write(reqMethod & " " & url & " HTTP/1.1\c\L")#Content-baseLen: 0\c\L\c\L")

proc writeHead*(x: var RequestBuffer, reqMethod: string, url: string, 
                headers: openarray[tuple[key, value: string]]) =
  x.write(reqMethod & " " & url & " HTTP/1.1\c\L")#Content-baseLen: 0\c\L\c\L")
  for it in headers:
    x.write(it.key & ": " & it.value & "\c\L")
  x.write("\c\L")

proc clear0*(x: var HttpBuffer) =
  x.realSize = x.pageSize
  x.base = newString(x.pageSize)
  x.baseLen = 0

proc clear*(x: var HttpBuffer) =
  x.realSize = x.pageSize
  x.base.setLen(x.pageSize)
  x.baseLen = 0

proc shallowCopyBase*(x: var HttpBuffer, y: var string) =
  shallowCopy(y, x.base)

proc len*(x: HttpBuffer): int = 
  result = x.baseLen

proc send*(socket: AsyncFD, buf: HttpBuffer, flags = {SocketFlag.SafeDisconn}) {.async.} =
  GC_ref(buf.base)
  try:
    await socket.send(buf.base.cstring, buf.baseLen, flags)
    GC_unref(buf.base)
  except:
    GC_unref(buf.base)
    raise getCurrentException()

proc send*(socket: AsyncSocket, buf: HttpBuffer, flags = {SocketFlag.SafeDisconn}) {.async.} =
  GC_ref(buf.base)
  try:
    await socket.send(buf.base.cstring, buf.baseLen, flags)
    GC_unref(buf.base)
  except:
    GC_unref(buf.base)
    raise getCurrentException()

proc sendTo*(socket: AsyncFD, buf: HttpBuffer, saddr: ptr SockAddr,
             saddrLen: SockLen, flags = {SocketFlag.SafeDisconn}) {.async.} =
  GC_ref(buf.base)
  try:
    await socket.sendTo(buf.base.cstring, buf.baseLen, saddr, saddrLen, flags)
    GC_unref(buf.base)
  except:
    GC_unref(buf.base)
    raise getCurrentException()

