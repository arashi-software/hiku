# TODO: use simd for all characters
import nimsimd/sse2
import strutils, tables, bitops

type
  DesktopEntry* = object
    name*: string
    icon*: string
    exec*: string

proc containsNonWhitespace(data: string, start, endPos: int): bool =
  # Check if the string contains any non-whitespace characters in the range
  var pos = start
  while pos < endPos:
    if not data[pos].isSpaceAscii:
      return true
    inc pos
  return false

proc findKey(data: string, startPos, endPos: int, key: string): int {.inline.} =
  # Find key position using SIMD
  let keyLen = key.len
  let keyFirst = mm_set1_epi8(key[0].char)
  
  var pos = startPos
  while pos < endPos - 16 and pos < data.len - 16:
    let chunk = mm_loadu_si128(cast[ptr M128i](unsafeAddr data[pos]))
    let matches = mm_cmpeq_epi8(chunk, keyFirst)
    let mask = mm_movemask_epi8(matches)
    
    if mask != 0:
      let firstMatch = countTrailingZeroBits(uint32(mask))
      let matchPos = pos + firstMatch
      if matchPos + keyLen <= endPos and matchPos + keyLen <= data.len:
        # Need to check if key is at beginning of line or after a newline
        if (matchPos == startPos or data[matchPos-1] == '\n') and 
           data[matchPos ..< matchPos + keyLen] == key:
          return matchPos
    pos += 1  # Move by just 1 character to ensure we don't miss anything
    
  # Handle remaining bytes
  while pos < endPos and pos < data.len:
    if data[pos] == key[0] and pos + keyLen <= endPos and pos + keyLen <= data.len:
      # Check if key is at beginning of line or after a newline
      if (pos == startPos or data[pos-1] == '\n') and
         data[pos ..< pos + keyLen] == key:
        return pos
    inc pos
  
  return -1

proc extractValue(data: string, keyPos: int, keyLen: int, endPos: int): string =
  # Extract value after key until newline or section end
  let valueStart = keyPos + keyLen
  if valueStart >= endPos:
    return ""
    
  var valueEnd = valueStart
  while valueEnd < endPos and valueEnd < data.len and data[valueEnd] != '\n':
    inc valueEnd
    
  result = data[valueStart ..< valueEnd].strip()

proc parseDesktopFile*(content: string): DesktopEntry =
  ## Parses an XDG .desktop file and returns name, icon and exec values
  ## using SIMD acceleration where possible
  result = DesktopEntry()
  
  const
    NameKey = "Name="
    IconKey = "Icon="
    ExecKey = "Exec="
    
  let contentLen = content.len
  
  # Find [Desktop Entry] section
  var sectionStart = findKey(content, 0, contentLen, "[Desktop Entry]")
  if sectionStart == -1:
    return
  sectionStart += "[Desktop Entry]".len
  
  # Find end of the section
  var sectionEnd = contentLen
  var nextSection = sectionStart
  
  while true:
    nextSection = content.find('[', nextSection)
    if nextSection != -1 and nextSection > sectionStart:
      # Make sure it's a section marker at the beginning of a line
      if nextSection == 0 or content[nextSection-1] == '\n':
        sectionEnd = nextSection
        break
      nextSection += 1
    else:
      break
  
  # Find Name
  let namePos = findKey(content, sectionStart, sectionEnd, NameKey)
  if namePos != -1:
    result.name = extractValue(content, namePos, NameKey.len, sectionEnd)
    # Skip if name is blank
    if result.name.len == 0 or not containsNonWhitespace(result.name, 0, result.name.len):
      return
  else:
    # Skip if no name found
    return
  
  # Find Icon
  let iconPos = findKey(content, sectionStart, sectionEnd, IconKey)
  if iconPos != -1:
    result.icon = extractValue(content, iconPos, IconKey.len, sectionEnd)
  
  # Find Exec
  let execPos = findKey(content, sectionStart, sectionEnd, ExecKey)
  if execPos != -1:
    result.exec = extractValue(content, execPos, ExecKey.len, sectionEnd)
    # Skip if exec is blank
    if result.exec.len == 0 or not containsNonWhitespace(result.exec, 0, result.exec.len):
      return
  else:
    # Skip if no exec found
    return
