#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

repository_url="${1:-git@github.com:Snuxx-code/UniPDF.git}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    git init -b main
fi

if git remote get-url origin >/dev/null 2>&1; then
    existing_origin="$(git remote get-url origin)"
    if [[ "$existing_origin" != "$repository_url" ]]; then
        if [[ "$existing_origin" == "https://github.com/Snuxx-code/UniPDF.git" && "$repository_url" == "git@github.com:Snuxx-code/UniPDF.git" ]]; then
            git remote set-url origin "$repository_url"
        else
            print -u2 "Abbruch: origin zeigt bereits auf $existing_origin. Die bestehende Verbindung bleibt erhalten."
            exit 1
        fi
    fi
else
    git remote add origin "$repository_url"
fi

if ! git diff --cached --quiet; then
    print -u2 "Abbruch: Es liegen bereits vorgemerkte Änderungen im Git-Index. Bitte diese zuerst separat committen oder aus dem Index nehmen."
    exit 1
fi

# Read the repository before committing or pushing anything.
git fetch origin
remote_head="$(git ls-remote --symref origin HEAD)"
remote_branch="$(print -r -- "$remote_head" | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p')"

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    if [[ -n "$remote_branch" ]]; then
        git check-ref-format --branch "$remote_branch" >/dev/null
        local_branch="$(git symbolic-ref --short HEAD)"
        if [[ "$local_branch" != "$remote_branch" ]]; then
            git branch -m "$remote_branch"
        fi
        # Adopt existing history while keeping the app files in the working tree.
        git reset --mixed "origin/$remote_branch"
        # Preserve remote-only files, including README/LICENSE additions outside this app.
        while IFS= read -r -d '' tracked_path; do
            if [[ ! -e "$tracked_path" && ! -L "$tracked_path" ]]; then
                git restore --worktree -- "$tracked_path"
            fi
        done < <(git ls-files -z)
    fi
fi

local_branch="$(git branch --show-current)"
if [[ -z "$local_branch" ]]; then
    print -u2 "Abbruch: Bitte zuerst einen lokalen Branch auswählen."
    exit 1
fi

# Only publish source, project documentation and build scripts; no generated app or PDFs.
git add -- .gitignore .impeccable/design.json DESIGN.md PRODUCT.md README.md \
    Package.swift Resources Sources Tests scripts

if ! git diff --cached --quiet; then
    git diff --cached --stat
    git commit -m "Add or update UniPDF app and project files"
fi

if git show-ref --verify --quiet "refs/remotes/origin/$local_branch"; then
    if ! git merge-base --is-ancestor "origin/$local_branch" HEAD; then
        print -u2 "Die lokale Arbeit ist committed. Der Remote-Branch enthält weitere Änderungen."
        print -u2 "Bitte diese zuerst mit git pull --rebase origin $local_branch zusammenführen. Es wurde nichts überschrieben oder gepusht."
        exit 1
    fi
fi

git push --set-upstream origin "$local_branch"
print "UniPDF ist mit $repository_url verbunden und hochgeladen."
