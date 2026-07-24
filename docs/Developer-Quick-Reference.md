Tower Developer Quick Reference

## Programmed Quick Links

Build
-----
tb      Build Tower

Run
---
tr
tr sensor
tr rf receive

Git
---
ta      git add .
tc      git commit
tp      git push
tg      git pull
ts      git status

Project
-------
tt      tree -L 2
tl      ls -lah

Repository
----------

## WinSCP Editing Workflow

- The user edits source code using WinSCP + Notepad++.
- Prefer giving repository-relative file paths (for example `src/main.cpp`) instead of `nano` commands.
- When requesting code changes, specify:
  - the file path;
  - the exact code to add/change;
  - optionally the approximate location.
- Asking the user to upload a file is possible.
- Use terminal commands for:
  - building;
  - running;
  - testing;
  - verifying specific line ranges or output.
- Always give the correct amount of indentations when pasting info, don't assume the amount.

----------
~/Development/rf-tower