#!/usr/bin/env python3
# Gate ask (DECISIONS V116): the browser, for chatgpt_signin.py's tests.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""fake_browser.py <url>: what a browser does with OpenAI's sign-in page
when the user signs in: the page (tests/fake_openai.py's authorize) is
fetched and its redirect followed to the helper's 127.0.0.1 callback.
Only for the tests: it never goes past 127.0.0.1."""
import sys
import urllib.parse
import urllib.request

u = sys.argv[1]
if urllib.parse.urlsplit(u).hostname != '127.0.0.1':
    sys.exit('fake_browser.py: only 127.0.0.1')
try:
    with urllib.request.urlopen(u, timeout=30) as r:
        r.read()
except Exception as e:                  # (the helper sees no callback: its own error)
    sys.stderr.write('fake_browser.py: %s\n' % e)
