This is the source directory for "Seeing the Invisble: Observability with Linkerd"
presented on 18 August 2022. In here you will find:

- `steps.sh`, the [demo-magic] script driving most of the presentation
- `create-cluster.sh`, a shell script to create a `k3d` cluster and prep it
  with [Linkerd], the [books] and [emojivoto] demo apps, and [Emissary-ingress]
  for the ingress
   - All of these things are installed mostly straight from the quickstart,
     except that we use `sed` to force everything to just one replica when
     installing Emissary. **DON'T** do that in production.

To actually run the workshop:

- Make sure the `emoji.example.com`, `books.example.com`, and `viz.example.com`
  all point to 127.0.0.1 (for example, by editing `/etc/hosts`).

- Make sure `$KUBECONFIG` is set correctly.

- If you need to, run `bash create-cluster.sh` to create a new `k3d` cluster to
  use.
   - **Note:** `create-cluster.sh` will delete any existing `k3d` cluster named
     "observability"

- Finally, run `bash steps.sh` to actually run the workshop demo! or just read it, and 
  run what it does by hand.

[books]: https://github.com/BuoyantIO/booksapp
[demo-magic]: https://github.com/paxtonhare/demo-magic/blob/master/demo-magic.sh
[Emissary-ingress]: https://www.getambassador.io/docs/emissary/
[emojivoto]: https://github.com/BuoyantIO/emojivoto
[Linkerd]: https://linkerd.io

---

#### HOOKS

When doing the demo live, especially as a livestream, it's nice to have the
demo automagically switch the screen you're sharing to the one that's relevant
at given points of the demo. However, if you're not doing this, it's a pain to
be constantly calling things that don't exist. Enter the `HOOK` setup.

At various points, the demo script will do e.g. `show_browser`, which turns
into a call to `run_hook BROWSER`. That will look for the `DEMO_HOOK_BROWSER`
environment variable: if it's defined, `run_hook` will execute the command in
`hook_browser`. If it's not defined, it gets silently skipped.

The end result: if you want to do fancy things, just set the requisite
`DEMO_HOOK_*` variables to the commands to do fancy things. If you don't set
the `DEMO_HOOK_*` variables, these steps will be silently skipped.
