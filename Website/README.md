# Website

The static site at [bettertg.su](https://bettertg.su): the landing page, [Support](support.html), the [Privacy Policy](privacy.html) and the [Terms of Service](terms.html). The app's Settings open `/privacy` and `/terms`, and App Store Connect links `/support` and `/privacy`, so keep those paths.

The pages are plain HTML and CSS with no build step. Open `index.html` in a browser to preview them.

## Deploying

Caddy on the VPS serves the directory `/var/www/bettertg.su`:

```caddy
bettertg.su {
    encode zstd gzip
    header {
        Strict-Transport-Security "max-age=31536000"
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
    }
    root * /var/www/bettertg.su
    try_files {path} {path}.html
    file_server
}
```

Copy the files over and Caddy picks them up without a reload:

```sh
rsync -av --delete --exclude README.md Website/ root@<host>:/var/www/bettertg.su/
```

Change the effective date at the top of a policy whenever its text changes.
