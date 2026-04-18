---
name: p5-gtk3-push
slug: p5-gtk3-push
version: 1.0.0
description: "Push P5-Gtk3-SourceEditor commits to GitHub. Use this skill whenever the user asks to push, commit and push, or sync the P5-Gtk3-SourceEditor repo to GitHub. Also use when the user mentions 'git push', 'push to github', 'upload commits', or similar."
---

## When to Use

Use this skill when the user asks to push P5-Gtk3-SourceEditor commits to GitHub,
or when work is done and needs to be uploaded.  Do NOT use for other repos or
projects.

## Important: Session Continuity

The token and exact push procedure are often lost during session compression.
This skill exists to prevent that.  Follow the procedure below exactly.

## Push Procedure

### Step 1: Ensure the remote URL is correct

The project lives at `https://github.com/nkh/z.git`.  The old repo
`nkh/P5-Gtk3-SourceEditor` is NO LONGER the push target.

```bash
cd /home/z/my-project/P5-Gtk3-SourceEditor
git remote get-url origin
```

If it shows anything other than `https://github.com/nkh/z.git`, fix it:

```bash
git remote set-url origin https://github.com/nkh/z.git
```

### Step 2: Ask the user for the token

The user will provide a GitHub fine-grained personal access token in the chat.
Do NOT attempt to push without a token — authentication will fail.

### Step 3: Set the remote URL with authentication

Use this EXACT URL format — username is `nkh`, password is the token, embedded
directly in the URL:

```bash
git remote set-url origin https://nkh:<TOKEN>@github.com/nkh/z.git
```

Where `<TOKEN>` is replaced with the token the user provided.

**Do NOT use `x-access-token` as the username.**  It must be `nkh`.

**Do NOT use `git credential approve` or credential helpers.**  They do not work
in this environment for fine-grained tokens.  The URL-embedded approach is the
only method that works.

### Step 4: Pull before pushing (rebase)

Always pull first to avoid divergence errors:

```bash
git pull --rebase origin main
```

### Step 5: Push

```bash
git push -u origin main
```

### Step 6: Display pushed commits

After a successful push, display a summary of what was pushed so the user can
see at a glance what went up.  Run:

```bash
git log --oneline origin/main@{1}..origin/main
```

Then present the output to the user with each commit on its own line.  This
shows the short SHA and subject for every commit that was just pushed.

### Step 7: Clean the remote URL

After pushing and displaying the summary, remove the token from the URL to
avoid storing credentials in plain text in the git config:

```bash
git remote set-url origin https://github.com/nkh/z.git
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 403 Permission denied | Wrong username in URL, or wrong repo URL | Ensure URL is `https://nkh:<TOKEN>@github.com/nkh/z.git` |
| Rejected (fetch first) | Remote has commits not in local | Run `git pull --rebase origin main` first |
| Divergent branches | Local and remote diverged | Run `git pull --rebase origin main` |
| Could not read Username | No credentials available | Token must be in the URL, not via credential helper |

## What NOT to do

- Do NOT push to `nkh/P5-Gtk3-SourceEditor` — the repo is now at `nkh/z`
- Do NOT use `x-access-token` as the username — use `nkh`
- Do NOT use `git credential store/cache/approve` — they don't work here
- Do NOT use `~/.netrc` or `~/.git-credentials` — they don't work here
- Do NOT use Bearer token headers — git uses Basic auth
- Do NOT use a classic token — fine-grained tokens work with the URL method above
