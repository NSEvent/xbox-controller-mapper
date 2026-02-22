"""
Generate vocab.txt from nltk's word corpus or a web source.
Run this once to create the vocabulary file.
"""

import os
import ssl
import sys


def generate_from_nltk():
    """Generate vocabulary from NLTK's word lists."""
    try:
        # Workaround for macOS SSL certificate issues
        ssl._create_default_https_context = ssl._create_unverified_context
        import nltk
        nltk.download("words", quiet=True)
        nltk.download("brown", quiet=True)
        from nltk.corpus import words, brown

        # Get frequency from Brown corpus
        freq = {}
        for word in brown.words():
            w = word.lower().strip()
            if w.isalpha() and 2 <= len(w) <= 20:
                freq[w] = freq.get(w, 0) + 1

        # Combine NLTK words dictionary AND Brown corpus words
        # Brown corpus contains actual English text, so it naturally includes
        # inflected forms (past tense, plurals, gerunds) that the NLTK words
        # dictionary misses.
        all_words = set()
        for w in words.words():
            w = w.lower().strip()
            if w.isalpha() and 2 <= len(w) <= 20:
                all_words.add(w)

        # Include all Brown corpus words (inflected forms!)
        all_words.update(freq.keys())

        # Sort by frequency (Brown corpus), then alphabetically for ties
        scored = []
        for w in all_words:
            scored.append((w, freq.get(w, 0)))

        scored.sort(key=lambda x: (-x[1], x[0]))
        vocab = [(w, f) for w, f in scored[:50000]]

        return vocab
    except ImportError:
        return None


def generate_builtin():
    """Generate vocabulary from system dictionary or built-in list."""
    words = set()

    # Try system dictionary
    dict_paths = ["/usr/share/dict/words", "/usr/share/dict/american-english"]
    for path in dict_paths:
        if os.path.exists(path):
            with open(path) as f:
                for line in f:
                    w = line.strip().lower()
                    if w.isalpha() and 2 <= len(w) <= 20:
                        words.add(w)
            break

    if not words:
        print("No word source found. Using minimal built-in vocabulary.")
        # Common English words as fallback
        common = """the of and to in is it you that he was for on are with as his they be at
        one have this from or had by not but what all were we when your can said there use an
        each which she do how their if will up other about out many then them these so some her
        would make like him into time has look two more write go see number no way could people
        my than first water been call who oil its now find long down day did get come made may
        part over new after also back any our just know take still well here need very year where
        most hand high place good give work old much right think say help low line before same
        mean start every too great tell men world small end does next name home try keep turn move
        must big even such because point school own might never last let thought city run house
        state play close while should air change between life real under few set left being along
        both children story put example head always live leave show side went hard through another
        off far ask land important eye light face country food body family different girl open night
        group quite read car young often thing seem together kind enough sure age why idea boy plan
        early fact large above once power money second want room already program book"""
        words = set(common.split())

    # Sort by word length (shorter = more common generally), then alphabetically
    vocab = [(w, 0) for w in sorted(words, key=lambda w: (len(w), w))]
    return vocab[:50000]


def get_computing_words():
    """Computing-environment words with boosted frequencies.

    These cover common macOS app names, shell commands, directory names,
    programming terms, and other words a user is likely to type in a
    computing context.  Frequencies are set high enough to beat obscure
    dictionary words but below the most common English words.
    """
    # (word, frequency) — only lowercase alpha, 2-12 chars
    FREQ_HIGH = 10000   # very common computing terms
    FREQ_MED = 7000     # common tools / dirs / concepts
    FREQ_LOW = 4000     # less common but still relevant

    words = {}

    # ── Shell / CLI commands ──
    for w in [
        "ls", "cd", "cp", "mv", "rm", "cat", "grep", "find", "sudo",
        "ssh", "scp", "git", "make", "pip", "npm", "brew", "curl",
        "wget", "tar", "zip", "unzip", "chmod", "chown", "kill",
        "echo", "exit", "pwd", "mkdir", "rmdir", "touch", "diff",
        "sed", "awk", "top", "ps", "df", "du", "man", "which",
        "alias", "export", "source", "eval", "exec", "xargs",
        "sort", "head", "tail", "less", "more", "wc", "tee",
        "ping", "dig", "nmap", "rsync", "tmux", "screen",
        "docker", "python", "ruby", "node", "swift", "cargo",
        "rustc", "clang", "gcc", "java", "perl", "bash", "zsh",
        "fish", "vim", "nano", "emacs", "xcodebuild",
    ]:
        if w.isalpha() and 2 <= len(w) <= 12:
            words[w] = FREQ_HIGH

    # ── macOS app names (single lowercase words) ──
    for w in [
        "finder", "safari", "chrome", "firefox", "slack", "discord",
        "spotify", "music", "photos", "pages", "numbers", "keynote",
        "xcode", "terminal", "preview", "calendar", "messages",
        "notes", "reminders", "maps", "mail", "weather", "clock",
        "news", "stocks", "podcasts", "books", "facetime",
        "settings", "figma", "sketch", "notion", "obsidian",
        "linear", "zoom", "teams", "cursor", "warp", "iterm",
        "sublime", "vscode", "steam", "blender", "unity",
        "docker", "postman", "insomnia", "raycast", "alfred",
    ]:
        if w.isalpha() and 2 <= len(w) <= 12:
            words.setdefault(w, FREQ_MED)

    # ── Common directories / paths ──
    for w in [
        "home", "desktop", "documents", "downloads", "pictures",
        "videos", "library", "applications", "usr", "bin", "etc",
        "var", "tmp", "opt", "src", "lib", "config", "cache",
        "local", "share", "logs", "data", "backup", "public",
        "private", "dev", "build", "dist", "node", "vendor",
        "assets", "static", "templates", "scripts", "tests",
        "docs", "tools", "packages", "modules",
    ]:
        if w.isalpha() and 2 <= len(w) <= 12:
            words.setdefault(w, FREQ_MED)

    # ── Programming / tech terms ──
    for w in [
        "api", "url", "http", "https", "html", "css", "json",
        "yaml", "xml", "sql", "tcp", "udp", "dns", "ssh",
        "ftp", "cli", "gui", "ide", "sdk", "jwt", "oauth",
        "async", "await", "fetch", "push", "pull", "merge",
        "commit", "branch", "deploy", "debug", "build", "test",
        "lint", "format", "compile", "runtime", "server", "client",
        "proxy", "cache", "queue", "stack", "heap", "thread",
        "mutex", "token", "hash", "crypt", "auth", "admin",
        "root", "user", "host", "port", "route", "query",
        "param", "args", "flag", "env", "stdin", "stdout",
        "stderr", "pipe", "fork", "exec", "daemon", "cron",
        "log", "trace", "error", "warn", "info", "fatal",
        "null", "void", "bool", "int", "float", "string",
        "array", "dict", "list", "map", "set", "enum", "struct",
        "class", "func", "init", "self", "super", "import",
        "export", "return", "yield", "break", "switch", "case",
        "default", "throw", "catch", "try", "defer", "guard",
        "static", "const", "let", "var", "type", "protocol",
        "interface", "abstract", "virtual", "override", "public",
        "private", "internal", "module", "package", "crate",
        "lambda", "closure", "callback", "promise", "stream",
        "buffer", "socket", "request", "response", "header",
        "cookie", "session", "webhook", "endpoint", "schema",
        "migration", "container", "cluster", "pod", "volume",
        "image", "network", "firewall", "gateway", "load",
        "balancer", "replica", "shard", "index", "table",
        "column", "row", "key", "value", "node", "edge",
        "graph", "tree", "queue", "deque", "vector", "tuple",
        "regex", "glob", "path", "file", "folder", "link",
        "symlink", "mount", "swap", "kernel", "shell", "reboot",
        "update", "upgrade", "install", "remove", "purge",
        "config", "setup", "init", "reset", "status", "version",
        "release", "tag", "issue", "review", "approve", "block",
        "merge", "rebase", "stash", "clone", "fetch", "remote",
        "origin", "upstream", "master", "main", "develop",
        "feature", "hotfix", "patch", "minor", "major",
        "frontend", "backend", "devops", "cloud", "saas",
        "micro", "macro", "plugin", "addon", "widget",
        "modal", "popup", "toast", "badge", "icon", "avatar",
        "theme", "layout", "grid", "flex", "margin", "padding",
        "border", "shadow", "opacity", "gradient", "font",
        "color", "style", "hover", "focus", "active", "toggle",
        "scroll", "drag", "drop", "resize", "animate",
        "render", "mount", "unmount", "props", "state",
        "redux", "store", "action", "reducer", "dispatch",
        "context", "provider", "consumer", "hook", "effect",
        "memo", "ref", "portal", "slot", "emit", "bind",
        "model", "view", "scope", "inject", "resolve",
        "singleton", "factory", "observer", "adapter", "proxy",
        "iterator", "generator", "decorator", "middleware",
        "handler", "listener", "emitter", "parser", "lexer",
        "compiler", "linker", "loader", "bundler", "minify",
        "uglify", "polyfill", "shim", "vendor", "chunk",
        "lazy", "eager", "batch", "bulk", "atomic", "idempotent",
        "webhook", "payload", "serialize", "encode", "decode",
        "encrypt", "decrypt", "sign", "verify", "validate",
        "sanitize", "escape", "throttle", "debounce", "retry",
        "timeout", "interval", "poll", "watch", "notify",
        "subscribe", "publish", "broadcast", "multicast",
        "localhost", "loopback", "subnet", "domain", "record",
        "alias", "cname", "proxy", "tunnel", "bridge",
        "swipe", "cursor", "mouse", "keyboard", "controller",
        "gamepad", "joystick", "button", "trigger", "bumper",
        "haptic", "vibrate", "rumble", "profile", "mapping",
        "binding", "shortcut", "hotkey", "macro", "script",
        "automate", "workflow", "pipeline", "task", "job",
        "process", "service", "worker", "agent", "bot",
        "prompt", "chat", "message", "reply", "send",
        "receive", "inbox", "outbox", "draft", "archive",
        "trash", "spam", "filter", "label", "tag",
        "search", "index", "rank", "score", "match",
        "suggest", "complete", "predict", "infer",
    ]:
        if w.isalpha() and 2 <= len(w) <= 12:
            words.setdefault(w, FREQ_LOW)

    return words


def get_installed_app_names():
    """Scan /Applications for single-word app names on the current machine."""
    import subprocess
    words = {}
    try:
        result = subprocess.run(
            ["ls", "/Applications"],
            capture_output=True, text=True, timeout=5,
        )
        for name in result.stdout.splitlines():
            # Use only the basename, strip .app suffix
            app = os.path.basename(name).replace(".app", "").strip()
            # Only single-word, alpha-only names
            w = app.lower()
            if w.isalpha() and 2 <= len(w) <= 12:
                words[w] = 7000
    except Exception:
        pass
    return words


def main():
    print("Generating vocabulary...")

    vocab = generate_from_nltk()
    if vocab is None:
        print("NLTK not available, using system dictionary...")
        vocab = generate_builtin()

    # Merge computing words — boost existing or add new entries
    vocab_dict = {w: f for w, f in vocab}
    computing = get_computing_words()
    installed = get_installed_app_names()

    for source_name, source in [("computing", computing), ("installed apps", installed)]:
        added = 0
        boosted = 0
        for w, freq in source.items():
            old = vocab_dict.get(w, 0)
            if freq > old:
                vocab_dict[w] = freq
                if old > 0:
                    boosted += 1
                else:
                    added += 1
        print(f"  {source_name}: {added} added, {boosted} boosted")

    # Re-sort and cap at 50000
    scored = sorted(vocab_dict.items(), key=lambda x: (-x[1], x[0]))
    vocab = scored[:50000]

    output_path = os.path.join(os.path.dirname(__file__), "vocab.txt")
    with open(output_path, "w") as f:
        for word, freq in vocab:
            f.write(f"{word}\t{freq}\n")

    print(f"Wrote {len(vocab)} words to {output_path}")


if __name__ == "__main__":
    main()
