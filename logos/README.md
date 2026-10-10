# Proof Network logo options

1. [logo-1.png](logo-1.png) — Mascot: a friendly lime-green frog scientist with white hair, gold spectacles and electric-blue eyes on midnight navy.
2. [logo-2.png](logo-2.png) — Geometric icon: a bold frog face, oversized circular glasses and a white hair silhouette on cobalt; selected for the wallet mark.
3. [logo-3.png](logo-3.png) — Lettermark: chunky PROOF lettering with the two O's forming the scientist's gold spectacles.
4. [logo-4.png](logo-4.png) — Minted emblem: a sculpted frog portrait in a silver coin rim with an electric-cyan inset.
5. [logo-5.png](logo-5.png) — Meme illustration: an expressive frog scientist tapping his temple against a vivid blue comic burst.

All five images were drawn with OpenAI's built-in `image_gen` tool, using the [creator's image](https://fxumiqjngmabtgvruvka.supabase.co/storage/v1/object/public/forum-attachments/posts/mv2e1bfu-r258kw.webp) as the subject and palette reference. Five drafts were generated, one per approach; all five were retained, with no discarded drafts or retries. They were resampled to 1024×1024 RGB PNGs without adding or redrawing artwork. No code-drawn fallback was needed. The backgrounds are opaque and fill the square.

[artifacts/logo.png](../artifacts/logo.png) is an identical copy of option 2. It was inspected as a 32-pixel circle on both light and dark backgrounds: the glasses, frog face and white hair remain distinct, with no lettering, enclosing frame or blank margin. All five options were also inspected at 64 pixels as squares and circles on light and dark backgrounds. Option 2 is the strongest small wallet mark: options 1 and 5 have more illustrative detail, option 3 intentionally contains the ticker, and option 4 intentionally contains a coin rim. Those features suit their requested approaches but are less suitable for the primary wallet mark.

The generation prompt set is recorded in [PROMPTS.md](PROMPTS.md); image hashes and processing provenance are in [provenance.json](provenance.json).
