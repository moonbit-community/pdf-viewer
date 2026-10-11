# Web viewer and GitHub Pages

The public website runs the existing MoonBit/Rabbita reader. Open a local PDF
with **选择 PDF 文件** or drag it onto the page. Reading, search, thumbnails,
layers, printing, annotations, form filling and visual signatures use the same
application as the development server. Local files stay in the browser; saving
downloads an edited PDF.

## Enable the website

1. Open the repository's **Settings → Pages**.
2. Set **Build and deployment → Source** to **GitHub Actions**.
3. Open **Actions → GitHub Pages → Run workflow**, using `master`.

The default project URL is
<https://moonbit-community.github.io/pdf-viewer/>. The deployment job also reports
the actual URL, including a custom domain if one is configured.

The [Pages workflow](../.github/workflows/pages.yml) builds and verifies the
website on pushes to `master`, pull requests and manual runs. It uses the
repository's verified MoonBit toolchain and locked npm assets, compiles both
MoonBit browser packages, minifies their generated modules with the existing
locked esbuild, and tests the published directory in Chromium and
WebKit at 2× pixel density under `/pdf-viewer/`. The checks exercise actual Worker
paint, search, layer switching, form editing/save/reopen, XFA layout and the
packaged Wasm files. A six-page image and text fixture also checks scrolling
during loading, cancellation, responsive controls and nonblank page pixels.
They do not require the local PDF.js comparison checkout.

Deployment runs after the build succeeds, for `master` only. Until Pages is
enabled with GitHub Actions as its source, the workflow uploads the verified
site artifact and skips deployment. After enabling Pages, run the workflow
manually once; subsequent pushes to `master` deploy automatically. Pull requests
build and test the site without deploying it.

The deployment job grants `pages: write` and `id-token: write` to GitHub's Pages
actions. No personal access token is needed. See
[GitHub's custom workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

## Build and preview locally

```sh
moon install
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon run tools/build_pages.mbtx
python3 -m http.server 4312 --directory _build/pages
```

Open <http://localhost:4312/>. Deploy the contents of `_build/pages/` to any
static HTTP host. All runtime URLs are relative, including Worker imports,
LittleCMS/JBIG2 Wasm and XFA CSS, so the site also runs under a repository path.
The published directory includes generated modules, codec assets and licenses;
it excludes development PDFs in `web/_test/` and the comparison checkout.
`.nojekyll` is included for static hosts that otherwise process the directory
with Jekyll.

To run the same subpath check locally:

```sh
npm ci --prefix tools/test-host --ignore-scripts
tools/test-host/node_modules/.bin/playwright install chromium webkit
node tools/pages_browser_test.mjs
PDF_BROWSER=webkit node tools/pages_browser_test.mjs
```

Reports and downloaded PDFs are written to `_build/pages-test-*/` and retained
by the workflow. The test starts and stops its own static HTTP server.

The existing `?file=...` parameter can load a relative or remote PDF URL.
For example, `?file=./example.pdf#page=2` opens a PDF served beside the site.
Remote servers must allow browser requests from the website's origin.
