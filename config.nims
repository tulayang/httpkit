import ospaths, strutils

proc reGenDoc(filename: string) =
  writeFile(filename,
            replace(
              replace(readFile(filename), 
                      """href="/tree/master/httpkit""", 
                      """href="https://github.com/tulayang/httpkit/tree/master/httpkit""" ),
              """href="/edit/devel/httpkit""",
              """href="https://github.com/tulayang/httpkit/edit/master/httpkit""" ))

template runTest(name: string) =
  withDir thisDir():
    mkDir "bin"
    --r
    --o:"""bin/""" name
    --verbosity:0
    --path:"""."""
    setCommand "c", "test/" & name & ".nim"

task doc, "Generate documentation":
  for name in [
    "parser",  "growbuffer"
  ]:
    exec "nim doc2 -o:$outfile --docSeeSrcUrl:$url $file" % [
      "outfile", thisDir() / "doc" / name & ".html",
      "url",     "https://github.com/tulayang/nimnode/blob/master",
      "file",    thisDir() / "httpkit" / name & ".nim"
    ]
    reGenDoc thisDir() / "doc" / name & ".html"
  exec "nim rst2html -o:$outfile $file" % [
    "outfile", thisDir() / "doc" / "index.html",
    "file",    thisDir() / "doc" / "index.rst"
  ]

task test, "Run test tests":
  runTest "test"
