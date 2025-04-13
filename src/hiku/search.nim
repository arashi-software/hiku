import floof
import desktop
import std/[algorithm, sequtils, strutils, tables, strformat] # Added tables and strformat for the example

type
  DesktopEntrySearchResult* = object
    entry*: DesktopEntry
    score*: float32

proc floofy*(entries: seq[DesktopEntry], query: string, 
                                     maxResults: int = 10): seq[DesktopEntrySearchResult] =
  ## Search through desktop entries using floof's SIMD-accelerated fuzzy matching.
  ## Searches **only** the `name` field.
  ## Returns up to maxResults entries sorted by match score (highest first).
  if entries.len == 0 or query.len == 0:
    return @[]

  var results = newSeqOfCap[DesktopEntrySearchResult](entries.len)
  
  # Extract ONLY name fields for floof search
  let names = entries.mapIt(it.name)
  
  # Perform search using floof's API only on names
  let searchResults = search(query, names)
  
  # Create lookup table from search results for O(1) lookup
  var scoreByName = initTable[string, float32]()
  for sr in searchResults:
    # Handle potential duplicate names (though less likely for desktop entries)
    # Keep the highest score if duplicates exist in the input `names`
    if scoreByName.hasKeyOrPut(sr.text, sr.score):
      scoreByName[sr.text] = max(scoreByName[sr.text], sr.score)
      
  # Map results back to original entries
  for entry in entries:
    # Use getOrDefault to avoid errors if a name wasn't found (score might be low)
    let score = scoreByName.getOrDefault(entry.name, 0.0'f32) 
    if score > 0: # Only add entries that had some match score
        results.add(DesktopEntrySearchResult(
            entry: entry,
            score: score
        ))
          
  # Sort by score (highest first), then by name length (shortest first) as a tie-breaker
  sort(results, proc(x, y: DesktopEntrySearchResult): int =
    result = cmp(y.score, x.score) # Higher score first
    if result == 0:
      result = cmp(x.entry.name.len, y.entry.name.len) # Shorter name first on tie
  )
  
  # Return up to maxResults
  if results.len <= maxResults:
    return results
  else:
    return results[0 ..< maxResults]
