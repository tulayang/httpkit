#    HttpKit - An efficient HTTP tool suite written in pure nim
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import strtabs, strutils, net, asyncnet, asyncdispatch, util

type
  LineState = enum
    lpInit, lpCRLF, lpOK

  Line = object
    base: string
    size: int
    sizeLimit: int
    state: LineState

proc initLine(sizeLimit = 1024): Line =
  result.sizeLimit = sizeLimit
  result.base = newStringOfCap(sizeLimit)

proc clear(line: var Line) =
  line.base.setLen(0)
  line.size = 0
  line.state = lpInit

proc read(line: var Line, buf: pointer, size: int): int =
  result = 0
  while result < size:
    let c = cast[ptr char](offsetChar(buf, result))[] 
    case line.state
    of lpInit:
      if c == '\r':
        line.state = lpCRLF
      else:
        line.base.add(c)
        line.size.inc(1)
        if line.size >= line.sizeLimit:
          raise newException(ValueError, "internal buffer overflow")
    of lpCRLF:
      if c == '\L':
        line.state = lpOK
        result.inc(1)
        line.base.setLen(result-2)
        return
      else:
        raise newException(ValueError, "invalid CRLF")
    of lpOK:
      return
    result.inc(1)

type
  ParsePhase = enum
    ppInit, ppProtocol, ppHeaders, ppCheck, ppUpgrade, ppData, ppChunkBegin, ppChunk, 
    ppDataEnd, ppError

  ParseState* = enum
    psRequest, psData, psDataChunked, psDataEnd, psExpect100Continue, psExceptOther, 
    psUpgrade, psError
                                                 
  Chunk = object
    base: pointer
    size: int
    pos: int
    dataSize: int

  HttpParser* = object
    reqMethod: string
    url: string
    protocol: tuple[orig: string, major, minor: int]
    headers: StringTableRef
    chunk: Chunk
    line: Line
    contentLength: int
    chunkLength: int
    headerLimit: int
    headerNums: int
    chunkedTransferEncoding: bool
    keepAlive*: bool
    phase: ParsePhase
    state: ParseState

template chunk: untyped = parser.chunk
template line: untyped = parser.line

proc initHttpParser*(lineLimit = 1024, headerLimit = 1024): HttpParser =
  result.headers = newStringTable(modeCaseInsensitive)
  result.line = initLine(lineLimit)
  result.headerLimit = headerLimit

proc pick(parser: var HttpParser, buf: pointer, size: int) =
  chunk.base = buf
  chunk.size = size
  chunk.pos = 0
  chunk.dataSize = 0

proc parseOnInit(parser: var HttpParser) =
  parser.reqMethod = ""
  parser.url = ""
  parser.protocol.orig = ""
  parser.protocol.major = 0
  parser.protocol.minor = 0 
  parser.headers.clear(modeCaseInsensitive) 
  parser.line.clear()
  parser.headerNums = 0
  parser.contentLength = 0
  parser.chunkLength = 0
  parser.chunkedTransferEncoding = false
  parser.keepAlive = false

proc parseOnProtocol(parser: var HttpParser): bool =
  while chunk.pos < chunk.size:
    let n = line.read(offsetChar(chunk.base, chunk.pos), chunk.size - chunk.pos)
    chunk.pos.inc(n)
    if line.state == lpOK:
      parseRequestProtocol(line.base, parser.reqMethod, parser.url, parser.protocol)
      line.clear() 
      return true
    else:
      assert chunk.pos == chunk.size 
  return false

proc parseOnHeaders(parser: var HttpParser): bool = 
  while chunk.pos < chunk.size:
    let n = line.read(offsetChar(chunk.base, chunk.pos), chunk.size - chunk.pos)
    chunk.pos.inc(n)
    if line.state == lpOK:
      if line.base == "":
        line.clear()
        return true
      parseHeader(line.base, parser.headers)
      line.clear() 
      parser.headerNums.inc(1)
      if parser.headerNums > parser.headerLimit:
        raise newException(ValueError, "header limit")
    else:
      assert chunk.pos == chunk.size
  return false

proc parseOnCheck(parser: var HttpParser) = 
  try:
    parser.contentLength = parseInt(parser.headers.getOrDefault("Content-Length"))
    if parser.contentLength < 0:
      parser.contentLength = 0
  except:
    parser.contentLength = 0
  if parser.headers.getOrDefault("Transfer-Encoding") == "bufed":
    parser.chunkedTransferEncoding = true
  if (parser.protocol.major == 1 and parser.protocol.minor == 1 and
      normalize(parser.headers.getOrDefault("Connection")) != "close") or
     (parser.protocol.major == 1 and parser.protocol.minor == 0 and
      normalize(parser.headers.getOrDefault("Connection")) == "keep-alive"):
    parser.keepAlive = true

iterator parse*(parser: var HttpParser, buf: pointer, size: int): ParseState =
  parser.pick(buf, size)
  while true:
    case parser.phase
    of ppInit:
      parser.parseOnInit()
      parser.phase = ppProtocol
    of ppProtocol:
      try:
        if parser.parseOnProtocol():
          parser.phase = ppHeaders
        else:
          break
      except:
        #parser.error = ...
        parser.phase = ppError
    of ppHeaders:
      try:
        if parser.parseOnHeaders():
          parser.phase = ppCheck
        else:
          break
      except:
        #parser.error = ...
        parser.phase = ppError
    of ppCheck:
      parser.parseOnCheck()
      if parser.headers.getOrDefault("Connection") == "Upgrade":
        parser.phase = ppUpgrade
        continue
      if parser.headers.hasKey("Expect"):
        if "100-continue" in parser.headers["Expect"]: 
          yield psExpect100Continue
        else:
          yield psExceptOther
      yield psRequest
      if parser.chunkedTransferEncoding:
        parser.phase = ppChunkBegin
        line.clear()
      elif parser.contentLength == 0:
        parser.phase = ppDataEnd
      else:
        parser.phase = ppData
    of ppData:
      let remained = chunk.size - chunk.pos
      if remained <= 0:
        break
      elif remained < parser.contentLength:
        chunk.dataSize = remained
        yield psData
        chunk.pos.inc(remained)
        parser.contentLength.dec(remained)
      else:
        chunk.dataSize = parser.contentLength
        yield psData
        chunk.pos.inc(parser.contentLength)
        parser.contentLength.dec(parser.contentLength)
        parser.phase = ppDataEnd
    of ppChunkBegin:
      let n = line.read(offsetChar(chunk.base, chunk.pos), chunk.size - chunk.pos)
      chunk.pos.inc(n)
      if line.state == lpOK:
        try:
          let chunkSize = parseChunkSize(line.base)
          if chunkSize <= 0:
            parser.phase = ppDataEnd
          else:
            parser.chunkLength = chunkSize + 2
            parser.phase = ppChunk
        except:
          #parser.error = ...
          parser.phase = ppError
      else:
        assert chunk.pos == chunk.size
        break
    of ppChunk:
      if parser.chunkLength <= 0:
        yield psDataChunked
        parser.phase = ppChunkBegin
        line.clear()
      elif parser.chunkLength == 1: # tail   \n
        let remained = chunk.size - chunk.pos
        if remained <= 0:
          break
        else:
          chunk.pos.inc(1)
          parser.chunkLength.dec(1)
      elif parser.chunkLength == 2: # tail \r\n
        let remained = chunk.size - chunk.pos
        if remained <= 0:
          break
        elif remained == 1:
          chunk.pos.inc(1)
          parser.chunkLength.dec(1)
        else:
          chunk.pos.inc(2)
          parser.chunkLength.dec(2)
      else:
        let remained = chunk.size - chunk.pos
        if remained <= 0:
          break
        elif remained <= parser.chunkLength - 2:
          chunk.dataSize = remained
          yield psData
          chunk.pos.inc(remained)
          parser.chunkLength.dec(remained)
        else:
          chunk.dataSize = parser.chunkLength - 2
          yield psData
          chunk.pos.inc(parser.chunkLength - 2)
          parser.chunkLength.dec(parser.chunkLength - 2)
    of ppDataEnd:
      parser.phase = ppInit
      yield psDataEnd
    of ppUpgrade:
      yield psUpgrade
      break
    of ppError:
      yield psError
      break

proc getData*(parser: var HttpParser): tuple[base: pointer, size: int] =
  result.base = offsetChar(chunk.base, chunk.pos)
  result.size = chunk.dataSize

proc getRemainPacket*(parser: var HttpParser): tuple[base: pointer, size: int] =
  result.base = offsetChar(chunk.base, chunk.pos)
  result.size = chunk.size - chunk.pos


