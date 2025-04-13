import os, strutils
import hiku/[apps, search]

proc main(): int =
  echo loadApps().floofy(commandLineParams().join())
  return 0

when isMainModule:
  quit main()
