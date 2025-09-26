#!/usr/bin/env nu

# Test script to check if autocompletions work

use amasia/snip

# Try to get completions for snip command
print "Testing snip completions..."

# This would show available snippets when hitting Tab
# snip -r <TAB>
# snip run <TAB>
# snip show <TAB>

# Let's list snippets to confirm they exist
print "\nAvailable snippets:"
snip ls

print "\nTo test autocompletion:"
print "1. Open a new Nu shell"
print "2. Run: use amasia/snip"
print "3. Type: snip -r <TAB>"
print "4. Type: snip run <TAB>"
print "5. You should see available snippets as completion options"