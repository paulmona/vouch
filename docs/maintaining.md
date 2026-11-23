# Maintaining the repository

For whoever owns a copy of this repository on GitHub and cuts releases from it.
Contributors do not need any of this.

## Repository settings

The workflows in `.github/workflows/` rely on settings that live in GitHub, not
in the tree. A new repository, or a fork that will publish its own releases,
has none of them: settings are not copied when a repository is created from
another, forked, or pushed to a new name. Do these in order. The order is for
a new public repository that starts from one commit: steps 0 to 6 are done
while it is still empty, step 7 is the first push, and the rest come after.

**Do step 1 before you store any secret and before you push any tag.** The
release workflows name an environment called `release`. Per GitHub's
documentation, a workflow that names an environment which does not exist makes
GitHub create it, empty: no reviewer and no rule about which tags may use it.
Every release job therefore stops at its first step unless the variable
`RELEASE_ENV_READY` is `true`, and step 1 is where you set it. That check
catches an environment that is missing or half made. It is no defence against
whoever writes the tagged commit: the check is a step in the workflow file, a
tag runs the workflow file of its own commit, and that file can leave the step
out. Against that, the reviewer and tag rules of step 1 and the tag ruleset of
step 2 are what hold.

0. **Create the repository public and empty.** If it takes the name of a
   repository you already have, deal with the old one first:
   - Rename the old repository (its Settings > General > Repository name).
   - In every clone of it, on every machine and for every agent that has
     one, run `git remote set-url origin <the renamed repository>` or
     `git remote remove origin`, then check with `git remote -v`. A clone's
     `origin` is the old name, and once the new repository has that name a
     routine push of any branch or tag from an old clone publishes the old
     history: the `main` ruleset of step 8 does not stop a new branch, and
     you are on the bypass list of the tag ruleset of step 2.

   Then create the new one. No README, licence or
   `.gitignore` added by GitHub, and nothing pushed yet. Do not announce it.
   It has to be public first: on GitHub's free plan, required reviewers,
   rulesets and private vulnerability reporting are offered only on a public
   repository, so steps 1, 2 and 3 cannot be done on a private one.

1. **The `release` environment.** Settings > Environments > New environment,
   named `release`. Then, on its page:
   - Tick **Required reviewers** and add yourself. Every release job then waits
     for your approval. GitHub offers this on a public repository, and on a
     private one only on some paid plans. If the option is not there, the tag
     rules below and the tag ruleset in step 2 are all that stand between a
     pushed tag and a release: nobody is asked first. Know that before
     you set the variable.
   - Leave **Prevent self-review** unticked while you are the only reviewer.
     With it ticked, the person who pushed the tag cannot approve the job, and
     there is nobody else to.
   - Under **Deployment branches and tags** choose "Selected branches and
     tags" and add three rules of type Tag: `server-v*`, `broker-v*` and
     `app-v*`. Add no branch rule.
   - Last, under **Environment variables**, add `RELEASE_ENV_READY` with the
     value `true`. Add it here, not under Settings > Secrets and variables >
     Actions > Variables: a repository variable is visible to every job, so it
     would say the environment is ready when it is not.

2. **Who may make a release tag.** Settings > Rules > Rulesets > New ruleset >
   New tag ruleset. Target the patterns `server-v*`, `broker-v*` and `app-v*`.
   Turn on "Restrict creations", "Restrict updates" and "Restrict deletions".
   A ruleset's bypass list takes roles, not a named user: put only the
   Repository admin role on it. Set the ruleset to Active.

3. **Private vulnerability reporting.** Settings > Code security > Private
   vulnerability reporting > Enable. `SECURITY.md` sends reporters to the page
   this turns on.

4. **Alerts and scanning.** On the same page, enable Dependabot alerts,
   Dependabot security updates, Secret scanning and **Push protection**.

5. **What Actions may do.** Settings > Actions > General:
   - "Workflow permissions": "Read repository contents and packages
     permissions".
   - Untick "Allow GitHub Actions to create and approve pull requests".
   - "Approval for running fork pull request workflows from contributors":
     "Require approval for all external contributors".

6. **Immutable releases.** Settings > General > Releases > enable release
   immutability. Per GitHub's documentation, a published release's tag and
   files then cannot be changed. A wrong release cannot be corrected and its
   tag cannot be used again: raise the version and release that.

7. **Push one commit and no tags.** Make the commit in a new directory, not
   in a clone of an older repository. Make the directory, empty, and fill it
   with
   `git -C <old clone> archive <commit> | tar -x -C <new directory>`: that
   writes the files tracked at that commit and nothing else. A plain
   recursive copy can carry `.git`, ignored files and untracked files. Then,
   in the new directory, `git init -b main`, `git add` the tree and
   `git commit -s`. The author name and email on that commit, and its
   `Signed-off-by` line, become public: if you do not want your own address
   there, set `user.email` in the new directory to your GitHub
   `users.noreply.github.com` address before you commit. Push the commit with
   `git push <remote> HEAD:main` and nothing else. Never use `--tags` or
   `--mirror`. A tag that reaches the new repository publishes the history
   behind it, and a `server-v*`, `broker-v*` or `app-v*` tag also starts the
   release workflow as it was written at that tag, which for a tag from
   before these checks existed has no `release` environment and no
   `RELEASE_ENV_READY` step. Then run `git ls-remote <remote>`: it must show
   one ref, `refs/heads/main` (with `HEAD` pointing at it), and no tag.
   Wait for CI on that commit. CI runs on pull requests, on each push to
   `main`, weekly, and by hand, so the push starts a `ci` run: look at the
   Actions tab, and if no run for the commit is green, start one (Actions >
   ci > Run workflow, branch `main`) and wait for it. That run needs no
   secrets: `ci.yml` reads none, so step 10 can wait.

8. **The `main` branch.** Do this after the first push and the first green run,
   not before: "Require a pull request before merging" would refuse the first
   commit, and the check `checks` cannot be picked until it has run once.
   Settings > Rules > Rulesets > New ruleset > New
   branch ruleset, targeting the default branch. Turn on "Require a pull
   request before merging" (leave its required approvals at 0 while you are
   the only maintainer: GitHub does not let you approve your own pull
   request), "Require status checks to pass" with the check
   `checks` and "Require branches to be up to date before merging", and "Block
   force pushes". Set it to Active.

9. **The `api-breaking` label.** Issues > Labels > New label, named
   `api-breaking`. CI skips its breaking-change check on a pull request that
   carries it (see `CONTRIBUTING.md`).

10. **The app's signing secrets.** On the `release` environment's page, under
    **Environment secrets**, add `ANDROID_UPLOAD_KEYSTORE_B64`,
    `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
    `ANDROID_KEY_PASSWORD` (`app/README.md` says what each holds). There is
    no Firebase secret: the published app is built with no Firebase config,
    so that it does not register phones with your Firebase project. If an
    earlier setup stored `GOOGLE_SERVICES_JSON` as a secret, delete it.
    Store them as environment secrets only. If any of the four is listed
    under Settings > Secrets and variables > Actions > Repository secrets,
    delete it there: a repository secret can be read by any workflow.

11. **The first releases.** See CI green on `main` before the first tag (step
    7). Before the first server tag, do the first part of step 12: an old
    `vouch-server` package must be gone before the release job pushes an
    image to that name. Then cut the server, broker and app releases as "Cutting a release"
    below says, and approve each job in the `release` environment. A tag
    must match the version in the tree, so raise a version by pull request
    first where it needs to change. Make each tag in the new directory from
    step 7, never in a clone of an older repository: an old clone already
    holds tags with these names, on commits of the old history. Bring the
    directory up to date (`git pull <remote> main`), check that
    `git rev-parse HEAD` is the commit `git ls-remote <remote>` shows for
    `refs/heads/main`, and tag that commit. Push the tag by name,
    `git push <remote> refs/tags/server-vX.Y.Z`, never with `--tags`. Then
    run `git ls-remote <remote>` again. It must show `main`, the tags you
    have just pushed, and no other tag. The only other refs should be those
    of pull requests opened since step 7 (`refs/pull/` and their branches).
    A tag or branch you cannot account for came from an old clone.
    `INSTALL.md`, `docs/broker.md` and the
    Docker guide point at release tags, the `:latest` image and a release
    APK, and none of those exist until you do.

12. **The container image, before and after the first server release.**
    Before it, look at your profile > Packages. If a `vouch-server`
    container package already exists under the account, delete the
    package. If your own server pulls that image, `docker compose pull`
    fails there until the first new release. A package belongs to the account, not to
    the repository, so renaming the old repository does not move it, and
    making an existing package public publishes every old image in it.
    With none there, the first
    `server-v*` release creates the `vouch-server` package, private. On the
    package's settings page (your profile > Packages > vouch-server > Package
    settings) change its visibility to Public and check that it is linked to
    this repository. Until then `docker pull` of the image fails for everyone
    else.

13. **Announce.** Only now tell anyone where the repository is. Until step
    12 is done a reader who follows `INSTALL.md` finds no release to install.

## Sign-off on commits

`CONTRIBUTING.md` asks for a `Signed-off-by` line on every commit. The `checks`
job enforces it on pull requests with `.github/check-signoff.sh`, so it needs
no setting and no app. It reads the commits in the pull request, not the commit
a merge writes to `main`: sign off the first commit of a new repository
yourself (`git commit -s`).

## Cutting a release

Raise the version on `main` by pull request (`server/package.json` and its
lockfile, `broker/pyproject.toml` and `uv.lock`, or `app/pubspec.yaml`), then
tag the merge commit `server-vX.Y.Z`, `broker-vX.Y.Z` or `app-vX.Y.Z` and push
the tag by name (`git push <remote> refs/tags/server-vX.Y.Z`). Each workflow
first waits for your approval, but only if the `release` environment has a
required reviewer (step 1): without one it starts at once. It then refuses a
tag that does not match the version in the tree or that is not on `main`.
