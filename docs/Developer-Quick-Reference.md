Tower Developer Quick Reference

For the user-facing Tower CLI reference using complete executable names, see
`docs/Commands.md`.

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

## Editing Workflow prompt instructions for ChatGPT

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
- If you past a large textblock for the docs files never use grave accent 3 times use /// instead.
- Always give the correct amount of indentations when pasting info, don't assume the amount.
- If you have multiple files that need edits give the files in the correct path order, meaning edit all files in src folder first then move to include folder to edit.
- When giving advice on a improvement also add the first steps to make that improvement in the text, this saves the user asking for the actual steps which will take another 40sec processing time.
- Same with explaining about a Commit you want to make, at the end ALWAYS add the first step for this improvement to keep the work flow high.
- From now on, for this project I'll treat the docs like source code:
  - Each document has its own fuction, try and preserve that
  - preserve existing content;
  - append new milestones;
  - mark completed items;
  - never remove history unless you explicitly ask.
----------
~/Development/rf-tower