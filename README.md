# kickstart.nvim

## Introduction

A starting point for Neovim that is:

* Small
* Single-file
* Completely Documented

**NOT** a Neovim distribution, but instead a starting point for your configuration.

## Java development

Java support lives in `lua/custom/java.lua`, loaded by `init.lua`. Mason installs
**JDTLS v1.61.0**. The checked-in `nvim-pack-lock.json` pins Neovim plugins,
including `nvim-jdtls`; keep it when cloning or copying this configuration.

### Reproduce after cloning

1. Clone this repo into `~/.config/nvim`, including its lockfile. Use **Neovim
   0.12.5** (the tested version), Git, Python **3.9+**, and a JDK containing
   `bin/java`, `release`, and `lib/src.zip`. Continuum requires **JDK 25**.
   Follow the external dependency instructions below for the rest of the config.
2. Set `JAVA_HOME` before starting Neovim. For Continuum, use the JDK supplied by
   its development environment. Check `"$JAVA_HOME/bin/java" -version` and
   `test -f "$JAVA_HOME/lib/src.zip"`. The config reads your environment rather
   than hardcoding a checkout-specific JDK installation path.
3. In the Continuum checkout, run `./gradlew --version` once to cache its wrapper
   distribution. Included builds without a wrapper (such as `build-logic`) use
   this same cached distribution instead of Buildship's older default Gradle.
4. Start `nvim` and let plugin and Mason installation finish. `vim.pack` installs
   the revisions in the lockfile. In `:Mason`, verify `jdtls` is installed; if
   necessary run `:MasonInstall jdtls@v1.61.0`. Restart after the first installation.
5. Open a Java file anywhere in Continuum. Let Fidget's import/indexing progress
   finish, then run `:JavaWorkspaceWarmup` once. It refreshes Gradle configuration
   and fully builds the Java workspace with Eclipse's compiler. It does not run
   distribution/native builds, start databases, or execute Omega tests.
6. Use `:JavaWorkspaceInfo` to check the root, JDK, source archive, cache, and logs.
   Warmup reports completion or errors; compiler diagnostics appear in quickfix.
   Build errors can coexist with usable navigation.

JDTLS uses the repository's Gradle wrapper and imports the enclosing multi-project
repository, including nested test and benchmark modules. Configuration updates,
annotation processing, and incremental Java builds are automatic. Generated
roots come from the build model rather than scanning every build directory.
JDK navigation uses `src.zip`. Dependencies open published sources when available
and can use decompiled contents otherwise.

Completion capabilities come from the existing Blink global LSP setup. Java adds
signature help, hover documentation, code actions, and refactorings. Formatting
keeps Conform's existing LSP fallback; organizing imports remains explicit.

### Keys and commands

| Key / command | Behavior |
| --- | --- |
| `grd` / `grD` | Definition / declaration, including JDK and dependency sources |
| `grr` | References across imported modules, including unopened files |
| `gri` / `grt` | Implementations / type definition |
| `K` / insert-mode `<C-k>` | Hover documentation / Blink signature-help toggle |
| `gra` / `grn` | Code actions / rename |
| `<leader>jo` | Organize Java imports |
| `<leader>jv` / `<leader>jc` | Extract variable / constant, normal or visual mode |
| Visual-mode `<leader>jm` | Extract method |
| `:JavaWorkspaceWarmup` | Refresh Gradle and fully rebuild the Java workspace |
| `:JavaWorkspaceRefresh` | Request configuration refresh without a full rebuild |
| `:JavaWorkspaceInfo` | Runtime, root, cache, client, warmup status, and logs |
| `:JdtRestart` / `:JdtShowLogs` | Restart Java support / open Java logs |

Annotations such as `FunctionalInterface` normally have no implementations;
definitions and references should work. Micronaut injection through annotations,
configuration, or generated beans is not necessarily an ordinary Java reference.
Framework bean browsing, debugging, and test runners are outside this setup.

### Cache and recovery

The existing `/home/opc/dev/graal-continuum` cache stays at
`~/.cache/nvim/jdtls/workspace/graal-continuum`. Other checkouts use a basename
and hash of their canonical root path. A session reuses one client per project;
restarts reuse saved indexes and perform startup/change checks. Warmup on every
file open is unnecessary. Caches and downloaded sources are recreated from this
configuration and remain machine-local.

The maximum Java server heap is 2 GiB. `JDTLS_JVM_ARGS` can add JVM arguments or
override that limit. On Linux, `lslocks` detects a workspace held by another
editor before launch; Eclipse also enforces its workspace lock. Close the other
editor before using the same workspace. A leftover lock file alone is not a live
lock. Never delete indexes while their server is running.

After dependency changes or branch switches, use `:JavaWorkspaceRefresh` or
`:JdtRestart` if automatic refresh has not caught up. Inspect quickfix and
`:JdtShowLogs` for classpath/compiler/processor failures; do not disable all
annotation processing to hide them. Historical Continuum logs contained a
`DocSnippetProcessor` error on a documentation `capture-isolate-id` attribute;
refreshing and rebuilding determines whether it persists in the current checkout.

The full workspace build reproduced that documentation error. It also found
that Continuum's `SavedAnnotationProcessor` uses javac internals, whereas JDTLS
builds with Eclipse's compiler. Some Micronaut test apps therefore cannot build
successfully inside JDTLS, even though ordinary Micronaut source navigation works.
Use their Gradle compilation for authoritative results. This configuration keeps
processors enabled and reports those failures; it does not modify Continuum's
processors or hide errors by disabling annotation processing globally.

For an actually corrupt workspace, `:JdtWipeDataAndRestart` is the plugin's
explicit, confirmation-based recovery command. The config never erases caches
automatically. A new machine or checkout path needs an initial import/indexing
pass. Upgrade JDTLS deliberately by changing its version in `init.lua`; review
and save lockfile changes after `vim.pack.update()`.

### Verify navigation

With no other editor using Continuum's workspace, run from this config repo:

```sh
nvim --headless -i NONE -c 'luafile scripts/check-java.lua'
```

To use a different checkout and fully warm it before checking:

```sh
JAVA_CHECK_ROOT=/path/to/graal-continuum JAVA_CHECK_WARMUP=1 \
  nvim --headless -i NONE -c 'luafile scripts/check-java.lua'
```

The script uses the real config and repository sources to check JDK/Micronaut
definition buffers, references from dependency buffers, references across
Continuum modules, implementations, and client reuse. It never saves source
edits. It also requests rename, import organization, extraction, and formatting
edits without applying them. Run it twice to compare first-run and cached
readiness; elapsed times are printed. Warmup errors are reported separately from
navigation results.
Dependency downloads may require the normal Continuum repository credentials.

## Installation

### Install Neovim

Kickstart.nvim targets *only* the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of Neovim.
If you are experiencing issues, please make sure you have at least the latest
stable version. Most likely, you want to install neovim via a [package
manager](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package).
To check your neovim version, run `nvim --version` and make sure it is not
below the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) version. If
your chosen install method only gives you an outdated version of neovim, find
alternative [installation methods below](#alternative-neovim-installation-methods).

### Install External Dependencies

External Requirements:
- Basic utils: `git`, `make`, `unzip`, C Compiler (`gcc`)
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation),
  [fd-find](https://github.com/sharkdp/fd#installation)
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md#installation)
- Clipboard tool (xclip/xsel/win32yank or other depending on the platform)
- A [Nerd Font](https://www.nerdfonts.com/): optional, provides various icons
  - if you have it set `vim.g.have_nerd_font` in `init.lua` to true
- Emoji fonts (Ubuntu only, and only if you want emoji!) `sudo apt install fonts-noto-color-emoji`
- Language Setup:
  - If you want to write Typescript, you need `npm`
  - If you want to write Golang, you will need `go`
  - etc.

> [!NOTE]
> See [Install Recipes](#Install-Recipes) for additional Windows and Linux specific notes
> and quick install snippets

### Install Kickstart

> [!NOTE]
> [Backup](#FAQ) your previous configuration (if any exists)

Neovim's configurations are located under the following paths, depending on your OS:

| OS | PATH |
| :- | :--- |
| Linux, MacOS | `$XDG_CONFIG_HOME/nvim`, `~/.config/nvim` |
| Windows (cmd)| `%localappdata%\nvim\` |
| Windows (powershell)| `$env:LOCALAPPDATA\nvim\` |

#### Recommended Step

Create your own copy of this repo using GitHub's
["Use this template"](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)
button so that you have your own copy that you can modify, then install by
cloning your new repo to your machine using one of the commands below,
depending on your OS.

Alternatively, you can [fork](https://docs.github.com/en/get-started/quickstart/fork-a-repo)
this repo if you prefer an easy upstream sync path (e.g., keeping your config
on a separate branch and fast-forwarding `master` from upstream). See the
[discussion in #1740](https://github.com/nvim-lua/kickstart.nvim/issues/1740)
for the tradeoffs between the two approaches.

> [!NOTE]
> Your repo's URL will be something like this:
> `https://github.com/<your_github_username>/kickstart.nvim.git`

You likely want to remove `nvim-pack-lock.json` from your repo's `.gitignore`
file too - it's ignored in the kickstart repo to make maintenance easier, but
it's recommended to track it in version control (see `:help vim.pack-lockfile`).

#### Clone kickstart.nvim

> [!NOTE]
> If following the recommended step above (i.e., creating your own repo from
> the template or fork), replace `nvim-lua` with `<your_github_username>`
> in the commands below

<details><summary> Linux and Mac </summary>

```sh
git clone https://github.com/nvim-lua/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
```

</details>

<details><summary> Windows </summary>

If you're using `cmd.exe`:

```
git clone https://github.com/nvim-lua/kickstart.nvim.git "%localappdata%\nvim"
```

If you're using `powershell.exe`

```
git clone https://github.com/nvim-lua/kickstart.nvim.git "${env:LOCALAPPDATA}\nvim"
```

</details>

### Post Installation

Start Neovim

```sh
nvim
```

That's it! `vim.pack` will install all the plugins from your config. Use
`:lua vim.pack.update(nil, { offline = true })` to inspect plugin state and
`:lua vim.pack.update()` to fetch updates (`:write` applies updates, `:quit`
cancels them).

#### Read The Friendly Documentation

Read through the `init.lua` file in your configuration folder for more
information about extending and exploring Neovim. That also includes
examples of adding popularly requested plugins.

> [!NOTE]
> For more information about a particular plugin check its repository's documentation.


### Getting Started

[The Only Video You Need to Get Started with Neovim](https://youtu.be/m8C0Cq9Uv9o)

### FAQ

* What should I do if I already have a pre-existing Neovim configuration?
  * You should back it up and then delete all associated files.
  * This includes your existing init.lua and the Neovim files in `~/.local`
    which can be deleted with `rm -rf ~/.local/share/nvim/`
* Can I keep my existing configuration in parallel to kickstart?
  * Yes! You can use [NVIM_APPNAME](https://neovim.io/doc/user/starting.html#%24NVIM_APPNAME)`=nvim-NAME`
    to maintain multiple configurations. For example, you can install the kickstart
    configuration in `~/.config/nvim-kickstart` and create an alias:
    ```
    alias nvim-kickstart='NVIM_APPNAME="nvim-kickstart" nvim'
    ```
    When you run Neovim using `nvim-kickstart` alias it will use the alternative
    config directory and the matching local directory
    `~/.local/share/nvim-kickstart`. You can apply this approach to any Neovim
    distribution that you would like to try out.
* What if I want to "uninstall" this configuration:
  * Remove your config directory and local data directory (for example,
    `~/.config/nvim` and `~/.local/share/nvim`).
* Why is the kickstart `init.lua` a single file? Wouldn't it make sense to split it into multiple files?
  * The main purpose of kickstart is to serve as a teaching tool and a reference
    configuration that someone can easily use to `git clone` as a basis for their own.
    As you progress in learning Neovim and Lua, you might consider splitting `init.lua`
    into smaller parts. A fork of kickstart that does this while maintaining the
    same functionality is available here:
    * [kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim)
  * Discussions on this topic can be found here:
    * [Restructure the configuration](https://github.com/nvim-lua/kickstart.nvim/issues/218)
    * [Reorganize init.lua into a multi-file setup](https://github.com/nvim-lua/kickstart.nvim/pull/473)

### Install Recipes

Below you can find OS specific install instructions for Neovim and dependencies.

After installing all the dependencies continue with the [Install Kickstart](#install-kickstart) step.

#### Windows Installation

<details><summary>Windows with Microsoft C++ Build Tools and CMake</summary>
Kickstart's default config is make-only for `telescope-fzf-native.nvim`.
If `make` is unavailable, the plugin is skipped.

Recommended: install `make` (see the chocolatey section below).

If you want a CMake-only setup, customize `init.lua` in two places:

1. Include `telescope-fzf-native.nvim` when `cmake` is available:

```lua
if vim.fn.executable 'make' == 1 or vim.fn.executable 'cmake' == 1 then
  table.insert(plugins, gh 'nvim-telescope/telescope-fzf-native.nvim')
end
```

2. In the `PackChanged` hook, use CMake when `make` is unavailable:

```lua
if name == 'telescope-fzf-native.nvim' then
  if vim.fn.executable 'make' == 1 then
    run_build(name, { 'make' }, ev.data.path)
  elseif vim.fn.executable 'cmake' == 1 then
    run_build(name, { 'cmake', '-S.', '-Bbuild', '-DCMAKE_BUILD_TYPE=Release' }, ev.data.path)
    run_build(name, { 'cmake', '--build', 'build', '--config', 'Release', '--target', 'install' }, ev.data.path)
  end
  return
end
```

See `telescope-fzf-native` documentation for [build details](https://github.com/nvim-telescope/telescope-fzf-native.nvim#installation).
</details>
<details><summary>Windows with gcc/make using chocolatey</summary>
Alternatively, one can install gcc and make which don't require changing the config,
the easiest way is to use choco:

1. install [chocolatey](https://chocolatey.org/install)
either follow the instructions on the page or use winget,
run in cmd as **admin**:
```
winget install --accept-source-agreements chocolatey.chocolatey
```

2. install all requirements using choco, exit the previous cmd and
open a new one so that choco path is set, and run in cmd as **admin**:
```
choco install -y neovim git ripgrep wget fd unzip gzip mingw make tree-sitter
```
</details>
<details><summary>WSL (Windows Subsystem for Linux)</summary>

```
wsl --install
wsl
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip neovim
```
</details>

#### Linux Install
<details><summary>Ubuntu Install Steps</summary>

```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip neovim
```
</details>
<details><summary>Debian Install Steps</summary>

```
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip curl

# Now we install nvim
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64
sudo mkdir -p /opt/nvim-linux-x86_64
sudo chmod a+rX /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# make it available in /usr/local/bin, distro installs to /usr/bin
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/
```
</details>
<details><summary>Fedora Install Steps</summary>

```
sudo dnf install -y gcc make git ripgrep fd-find tree-sitter-cli unzip neovim
```
</details>

<details><summary>Arch Install Steps</summary>

```
sudo pacman -S --noconfirm --needed gcc make git ripgrep fd tree-sitter-cli unzip neovim
```
</details>

<details><summary>Alpine Install Steps</summary>

> [!CAUTION]
> Neovim works fine on Alpine, but some tooling appears incompatible with musl
> (lua-language-server, etc., check `:Mason` or `:MasonLog`).
> Quickfix Lua-LSP-Support: `:%s/lua_ls/emmylua_ls`

```shell
sudo apk add gcc make git fd ripgrep tree-sitter-cli unzip bash gzip curl musl-dev neovim-doc neovim
```

</details>

### Alternative neovim installation methods

For some systems it is not unexpected that the [package manager installation
method](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package)
recommended by neovim is significantly behind. If that is the case for you,
pick one of the following methods that are known to deliver fresh neovim versions very quickly.
They have been picked for their popularity and because they make installing and updating
neovim to the latest versions easy. You can also find more detail about the
available methods being discussed
[here](https://github.com/nvim-lua/kickstart.nvim/issues/1583).


<details><summary>Bob</summary>

[Bob](https://github.com/MordechaiHadad/bob) is a Neovim version manager for
all platforms. Simply install
[rustup](https://rust-lang.github.io/rustup/installation/other.html),
and run the following commands:

```bash
rustup default stable
rustup update stable
cargo install bob-nvim
bob use stable
```

</details>

<details><summary>Homebrew</summary>

[Homebrew](https://brew.sh) is a package manager popular on Mac and Linux.
Simply install using [`brew install`](https://formulae.brew.sh/formula/neovim).

</details>

<details><summary>Flatpak</summary>

Flatpak is a package manager for applications that allows developers to package their applications
just once to make it available on all Linux systems. Simply [install flatpak](https://flatpak.org/setup/)
and setup [flathub](https://flathub.org/setup) to [install neovim](https://flathub.org/apps/io.neovim.nvim).

</details>

<details><summary>asdf and mise-en-place</summary>

[asdf](https://asdf-vm.com/) and [mise](https://mise.jdx.dev/) are tool version managers,
mostly aimed towards project-specific tool versioning. However both support managing tools
globally in the user-space as well:

<details><summary>mise</summary>

[Install mise](https://mise.jdx.dev/getting-started.html), then run:

```bash
mise plugins install neovim
mise use neovim@stable
```

</details>

<details><summary>asdf</summary>

[Install asdf](https://asdf-vm.com/guide/getting-started.html), then run:

```bash
asdf plugin add neovim
asdf install neovim stable
asdf set neovim stable --home
asdf reshim neovim
```

</details>

</details>
