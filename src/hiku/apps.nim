## Multithreaded app loader
import os, strutils, desktop, cpuinfo

type
  FileThreadData = object
    paths: seq[string]
    results: ptr seq[DesktopEntry]
    startidx: int
    endidx: int

func home*(): string {.inline.} =
  getHomeDir()

proc getAppDirs*(): seq[string] =
  let dirs =
    @[
      home() / ".nix-profile" / "share" / "applications",
      home() / ".local" / "share" / "applications",
      "/usr" / "share" / "applications",
      "/usr" / "local" / "share" / "applications",
    ]
  for dir in dirs:
    if dirExists dir:
      result.add dir

proc load(ctx: FileThreadData) {.thread.} =
  for i in ctx.startidx ..< ctx.endidx:
    ctx.results[] &= parseDesktopFile readFile(ctx.paths[i])

proc loadApps*(): seq[DesktopEntry] =
  let dirs = getAppDirs()
  var paths: seq[string]
  
  for dir in dirs:
    for kind, file in walkDir(dir):
      if kind notin {pcFile, pcLinkToFile}: continue
      let path =
        if kind == pcLinkToFile:
          expandSymlink(file)
        else:
          file
      if not path.endsWith(".desktop"): continue
      paths &= path
      
  let
    numThreads = countProcessors()
    chunkSize = paths.len div numThreads
    
  var
    threads: seq[Thread[FileThreadData]]
    threadResults: seq[ptr seq[DesktopEntry]]

  threads.setLen(numThreads)
  threadResults.setLen(numThreads)
  
  for i in 0 ..< numThreads:
    threadResults[i] = create(seq[DesktopEntry])
    threadResults[i][] = @[]
    
  var startIdx = 0
  for i in 0 ..< numThreads:
    let endIdx = min(startIdx + chunkSize, paths.len)
    if startIdx >= endIdx: break
    let threadData = FileThreadData(
      paths: paths,
      startidx: startIdx,
      endidx: endIdx,
      results: threadResults[i]
    )
    createThread(threads[i], load, threadData)
    startIdx += chunkSize

  for i in 0 ..< numThreads:
    if startIdx > i * chunkSize:
      joinThread(threads[i])
  result = @[]
  for i in 0 ..< numThreads:
    if startIdx > i * chunkSize:
      result.add(threadResults[i][])
      dealloc(threadResults[i])
