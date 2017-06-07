# HttpKit [![Build Status](https://travis-ci.org/tulayang/httpkit.svg?branch=master)](https://travis-ci.org/tulayang/httpkit)

This is an efficient HTTP tool suite written in pure nim. It can parse both requests and responses. Give it a data chunk, it will produce all the useful http states for you. And then, you can write your HTTP services with these states. 

## Features

* Does not perform IO operations, processing data chunk is its only purpose
* Data chunk can come from TCP socket, UDP socket, or even Unix Domain socket, etc. It means that you can write HTTP services via TCP, UDP, or even Unix Domain socket
* No overhead. If you are writing an asynchronous web service or clients by ``asyncdispatch`` and ``asyncnet``, HttpKit will not (create new ``Future`` to) increase overhead
* Be convenient to transfer large files. You can define your own data buffer, decide when to store datas and when to send datas
* Easy to extensible. For example, writing a websocket server or websocket parser

## Install

Releases are available as tags in this repository and can be fetched via nimble:

```sh
nimble install httpkit
```

**[API Documentation](https://tulayang.github.io/httpkit)**

