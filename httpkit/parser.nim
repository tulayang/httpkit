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

  ParseState = enum
    statHead, statData, statDataChunked, statDataEnd, statUpgrade, statError

  Chunk = object
    base: pointer
    size: int
    pos: int
    dataSize: int

  IHttpParser = concept var p
    p.parseOnInitHead()
    p.parseProtocol()
    p.chunk is Chunk
    p.line is Line
    p.contentLength is int
    p.chunkLength is int
    p.headerLimit is int
    p.headerNums is int
    p.chunkedTransferEncoding is bool
    p.keepAlive is bool
    p.phase is ParsePhase

template chunk: untyped = parser.chunk
template line: untyped = parser.line

proc pick(parser: var IHttpParser, buf: pointer, size: int) =
  chunk.base = buf
  chunk.size = size
  chunk.pos = 0
  chunk.dataSize = 0

proc parseOnInit(parser: var IHttpParser) = 
  parser.parseOnInitHead()
  parser.line.clear()
  parser.headerNums = 0
  parser.contentLength = 0
  parser.chunkLength = 0
  parser.chunkedTransferEncoding = false
  parser.keepAlive = false

proc parseOnProtocol(parser: var IHttpParser): bool =
  while chunk.pos < chunk.size:
    let n = line.read(offsetChar(chunk.base, chunk.pos), chunk.size - chunk.pos)
    chunk.pos.inc(n)
    if line.state == lpOK:
      parser.parseProtocol()
      line.clear() 
      return true
    else:
      assert chunk.pos == chunk.size 
  return false

proc parseOnHeaders(parser: var IHttpParser): bool = 
  while chunk.pos < chunk.size:
    let n = line.read(offsetChar(chunk.base, chunk.pos), chunk.size - chunk.pos)
    chunk.pos.inc(n)
    if line.state == lpOK:
      if line.base == "":
        line.clear()
        return true
      parseHeader(line.base, parser.head.headers)
      line.clear() 
      parser.headerNums.inc(1)
      if parser.headerNums > parser.headerLimit:
        raise newException(ValueError, "header limit")
    else:
      assert chunk.pos == chunk.size
  return false

proc parseOnCheck(parser: var IHttpParser) = 
  try:
    parser.contentLength = parseInt(parser.head.headers.getOrDefault("Content-Length"))
    if parser.contentLength < 0:
      parser.contentLength = 0
  except:
    parser.contentLength = 0
  if parser.head.headers.getOrDefault("Transfer-Encoding") == "bufed":
    parser.chunkedTransferEncoding = true
  if (parser.head.protocol.major == 1 and parser.head.protocol.minor == 1 and
      normalize(parser.head.headers.getOrDefault("Connection")) != "close") or
     (parser.head.protocol.major == 1 and parser.head.protocol.minor == 0 and
      normalize(parser.head.headers.getOrDefault("Connection")) == "keep-alive"):
    parser.keepAlive = true

iterator parse0(parser: var IHttpParser, buf: pointer, size: int): ParseState =
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
      if parser.head.headers.getOrDefault("Connection") == "Upgrade":
        parser.phase = ppUpgrade
        continue
      yield statHead
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
        yield statData
        chunk.pos.inc(remained)
        parser.contentLength.dec(remained)
      else:
        chunk.dataSize = parser.contentLength
        yield statData
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
        yield statDataChunked
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
          yield statData
          chunk.pos.inc(remained)
          parser.chunkLength.dec(remained)
        else:
          chunk.dataSize = parser.chunkLength - 2
          yield statData
          chunk.pos.inc(parser.chunkLength - 2)
          parser.chunkLength.dec(parser.chunkLength - 2)
    of ppDataEnd:
      parser.phase = ppInit
      yield statDataEnd
    of ppUpgrade:
      yield statUpgrade
      break
    of ppError:
      yield statError
      break

type
  RequestState* = enum
    statReqHead, statReqData, statReqDataChunked, statReqDataEnd,
    statReqExpect100Continue, statReqExceptOther, statReqUpgrade, statReqError

  ResponseState* = enum
    statResHead, statResData, statResDataChunked, statResDataEnd, statResUpgrade, statResError

  HttpParser* = object of RootObj
    chunk: Chunk
    line: Line
    contentLength: int
    chunkLength: int
    headerLimit: int
    headerNums: int
    chunkedTransferEncoding: bool
    keepAlive*: bool
    phase: ParsePhase

  RequestHead* = tuple
    reqMethod: string
    url: string
    protocol: tuple[orig: string, major, minor: int]
    headers: StringTableRef

  ResponseHead* = tuple
    statusCode: int
    statusMessage: string  
    protocol: tuple[orig: string, major, minor: int]
    headers: StringTableRef

  RequestParser* = object of HttpParser
    head: RequestHead

  ResponseParser* = object of HttpParser
    head: ResponseHead 

template initHttpParserImpl(lineLimit = 1024, headerLimit = 1024) {.dirty.} =
  result.head.headers = newStringTable(modeCaseInsensitive)
  result.line = initLine(lineLimit)
  result.headerLimit = headerLimit

proc initRequestParser*(lineLimit = 1024, headerLimit = 1024): RequestParser =
  initHttpParserImpl(lineLimit, headerLimit)

proc initResponseParser*(lineLimit = 1024, headerLimit = 1024): ResponseParser =
  initHttpParserImpl(lineLimit, headerLimit)

proc parseOnInitHead(parser: var RequestParser) {.inline.} = 
  parser.head.reqMethod = ""
  parser.head.url = "" 
  parser.head.protocol.orig = ""
  parser.head.protocol.major = 0
  parser.head.protocol.minor = 0
  parser.head.headers.clear(modeCaseInsensitive) 

proc parseOnInitHead(parser: var ResponseParser) {.inline.} = 
  parser.head.statusCode = 200
  parser.head.statusMessage = ""
  parser.head.protocol.orig = ""
  parser.head.protocol.major = 0
  parser.head.protocol.minor = 0
  parser.head.headers.clear(modeCaseInsensitive) 

proc parseProtocol(parser: var RequestParser) {.inline.} =
  parseRequestProtocol(line.base, parser.head.reqMethod, parser.head.url, parser.head.protocol)

proc parseProtocol(parser: var ResponseParser) {.inline.} = 
  parseResponseProtocol(line.base, parser.head.statusCode, parser.head.statusMessage, parser.head.protocol)

iterator parse*(parser: var RequestParser, buf: pointer, size: int): RequestState =
  for state in parser.parse0(buf, size):
    case state
    of statHead: 
      if parser.head.headers.hasKey("Expect"):
        if "100-continue" in parser.head.headers["Expect"]: 
          yield statReqExpect100Continue
        else:
          yield statReqExceptOther
      yield statReqHead
    of statData: yield statReqData
    of statDataChunked: yield statReqDataChunked
    of statDataEnd: yield statReqDataEnd
    of statUpgrade: yield statReqUpgrade
    of statError: yield statReqError

iterator parse*(parser: var ResponseParser, buf: pointer, size: int): ResponseState =
  for state in parser.parse0(buf, size):
    case state
    of statHead: 
      yield statResHead
    of statData: yield statResData
    of statDataChunked: yield statResDataChunked
    of statDataEnd: yield statResDataEnd
    of statUpgrade: yield statResUpgrade
    of statError: yield statResError

proc getHead*(parser: RequestParser): RequestHead =
  parser.head
  
proc getHead*(parser: ResponseParser): ResponseHead =
  parser.head

proc getData*(parser: RequestParser | ResponseParser): tuple[offset: int, size: int] =
  result.offset = chunk.pos
  result.size = chunk.dataSize

proc getRemainPacket*(parser: RequestParser | ResponseParser): tuple[offset: int, size: int] =
  result.offset = chunk.pos
  result.size = chunk.size - chunk.pos


