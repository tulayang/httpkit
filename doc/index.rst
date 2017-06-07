===============
NimNode Library
===============

:Author: Wang Tong
:Version: 0.1.1

.. contents::

  "You are not fighting alone!"

NimNode is a library for async programming and communication. This Library uses a future/promise, non-blocking I/O model based on libuv. `What is libuv? <http://libuv.org/>`_  `What is non-blocking I/O? <https://en.wikipedia.org/wiki/Asynchronous_I/O>`_ `What is event-driven? <https://en.wikipedia.org/wiki/Event-driven_programming>`_  `What are future and promise? <https://en.wikipedia.org/wiki/Futures_and_promises>`_

NimNode requires libuv library which should have been installed on your operating system. Releases are available as tags in this repository and can be fetched via nimble:

.. code-block:: sh

  nimble install node

Core modules
============

* `error <error.html>`_
  Provides error codes corresponding the libuv errornos. NimNode use these codes to indicate an internal error which caused by libuv operations.

* `loop <loop.html>`_
  Loop is the central part of functionality which depends on libuv event loop. It takes care of polling for i/o and scheduling callbacks to be run based on different sources of events.

* `timers <timers.html>`_
  This module implements a timer dispatcher and a ticker dispatcher. A timer delays an operation after some milliseconds. A ticker delays an operation to the next iteration.

* `future <future.html>`_
  This module is basically equivalent to the Future of standard library, in addition to a few special procedures.

* `streams <streams.html>`_
  This module implements a duplex (readable, writable) stream based on libuv. A stream is an abstract interface which provides reading and writing for non-blocking I/O.

* `net <net.html>`_
  Provides an asynchronous network wrapper. It contains functions for creating both servers and clients (called streams). 

* `httpcore <httpcore.html>`_
  Base utilities for processing http operations.

* `httpserver <httpserver.html>`_
  Provides infrastructure for building flexible and efficient HTTP server.

* `httpclient <httpclient.html>`_
  Provides infrastructure for building flexible and efficient HTTP client.

* `uv <uv.html>`_
  This module is a raw wrapper of libuv. It contains several sub modules.

  * `uv_error <uv/uv_error.html>`_
    In libuv errors are negative numbered constants. As a rule of thumb, whenever there is a status parameter, or an API functions returns an integer, a negative number will imply an error.

  * `uv_version <uv/uv_version.html>`_
    Starting with version 1.0.0 libuv follows the semantic versioning scheme. This means that new APIs can be introduced throughout the lifetime of a major release. In this section you’ll find all macros and functions that will allow you to write or compile code conditionally, in order to work with multiple libuv versions.

  * `uv_loop <uv/uv_loop.html>`_
    The event loop is the central part of libuv’s functionality. It takes care of polling for i/o and scheduling callbacks to be run based on different sources of events.

  * `uv_handle <uv/uv_handle.html>`_
    The base type for all libuv handle types.

  * `uv_request <uv/uv_request.html>`_
    The base type for all libuv request types.

  * `uv_timer <uv/uv_timer.html>`_
    Timer handles are used to schedule callbacks to be called in the future.

  * `uv_prepare <uv/uv_prepare.html>`_
    Prepare handles will run the given callback once per loop iteration, right before polling for i/o.

  * `uv_check <uv/uv_check.html>`_
    Check handles will run the given callback once per loop iteration, right after polling for i/o.

  * `uv_idle <uv/uv_idle.html>`_
    Idle handles will run the given callback once per loop iteration, right before the prepare handles.

  * `uv_async <uv/uv_async.html>`_
    Async handles allow the user to “wakeup” the event loop and get a callback called from another thread.

  * `uv_poll <uv/uv_poll.html>`_
    Poll handles are used to watch file descriptors for readability, writability and disconnection similar to the purpose of poll.

  * `uv_signal <uv/uv_signal.html>`_
    Signal handles implement Unix style signal handling on a per-event loop bases.

  * `uv_process <uv/uv_process.html>`_
    Process handles will spawn a new process and allow the user to control it and establish communication channels with it using streams.

  * `uv_stream <uv/uv_stream.html>`_
    Stream handles provide an abstraction of a duplex communication channel. stream is an abstract type, libuv provides 3 stream implementations in the for of tcp, pipe and tty.

  * `uv_tcp <uv/uv_tcp.html>`_
    TCP handles are used to represent both TCP streams and servers.

  * `uv_pipe <uv/uv_pipe.html>`_
    Pipe handles provide an abstraction over local domain sockets on Unix and named pipes on Windows.

  * `uv_tty <uv/uv_tty.html>`_
    TTY handles represent a stream for the console.

  * `uv_udp <uv/uv_udp.html>`_
    UDP handles encapsulate UDP communication for both clients and servers.

  * `uv_fs_event <uv/uv_fs_event.html>`_
    FS Event handles allow the user to monitor a given path for changes, for example, if the file was renamed or there was a generic change in it. This handle uses the best backend for the job on each platform.

  * `uv_fs_poll <uv/uv_fs_poll.html>`_
    FS Poll handles allow the user to monitor a given path for changes. Unlike fs event, fs poll handles use stat to detect when a file has changed so they can work on file systems where fs event handles can’t.

  * `uv_misc <uv/uv_misc.html>`_
    This section contains miscellaneous functions that don’t really belong in any other section.

Expansion packages
==================

These packages which do not belong to the core, provide additional features to support for heavy development.

.. raw:: html

  <div id="officialPkgList"></div>

