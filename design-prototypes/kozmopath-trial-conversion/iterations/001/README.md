# Kozmopath 14-day trial conversion · iteration 001

Standalone, no-network HTML prototypes for visual selection. Both landing directions preserve the approved Kozmopath product narrative and route trial entry to the shared local signup companion.

## Directions

- `variant-a-direct-trial/`: a conventional repeated-CTA path that puts the 14-day offer in the announcement, header, hero, and close.
- `variant-b-guided/`: a quieter landing shell whose primary action lives inside a product-specific trial runway attached to the conversation proof.
- `signup-companion/`: the shared signup destination. Its form validates locally and never sends a request.

## Local review

Serve this iteration root on loopback, then open the three directories. The verification and render scripts use `PROTOTYPE_BASE_URL` when set and default to `http://127.0.0.1:5089`.

```sh
node tests/verify-contract.mjs
node tests/verify-browser.mjs
node scripts/render.mjs
```

Production route mappings are evidence only. The prototypes never navigate to them.
