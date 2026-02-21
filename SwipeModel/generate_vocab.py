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

        # Also include common words from words corpus
        all_words = set()
        for w in words.words():
            w = w.lower().strip()
            if w.isalpha() and 2 <= len(w) <= 20:
                all_words.add(w)

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


def main():
    print("Generating vocabulary...")

    vocab = generate_from_nltk()
    if vocab is None:
        print("NLTK not available, using system dictionary...")
        vocab = generate_builtin()

    output_path = os.path.join(os.path.dirname(__file__), "vocab.txt")
    with open(output_path, "w") as f:
        for word, freq in vocab:
            f.write(f"{word}\t{freq}\n")

    print(f"Wrote {len(vocab)} words to {output_path}")


if __name__ == "__main__":
    main()
