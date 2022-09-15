This is the source directory for "A Deep Dive into Route-Based Policy",
presented on 15 September 2022. In here you will find:

- `steps.sh`, the [demo-magic] script driving most of the presentation
- `create-cluster.sh`, a shell script to create a `k3d` cluster and prep it
  with [Linkerd], the [books] and [emojivoto] demo apps, and [Emissary-ingress]
  for the ingress
   - `create-cluster.sh` uses `kustomize` for two purposes:
      - it allows any host to talk to the `linkerd-viz` dashboard, which you
        **MUST NOT DO IN PRODUCTION**, and
      - it scales Emissary down to one replica rather than three, to make it
        easier to work with e.g. `k3d`. Again, **not recommended in production**.

To actually run the workshop:

- Make sure that `emoji.example.com`, `books.example.com`, and `viz.example.com`
  all point to 127.0.0.1 (for example, by editing `/etc/hosts`).

- Make sure `$KUBECONFIG` is set correctly.

- If you need to, run `bash create-cluster.sh` to create a new `k3d` cluster to
  use.
   - **Note:** `create-cluster.sh` will delete any existing `k3d` cluster named
     "policy"

- Finally, run `bash steps.sh` to actually run the workshop demo! or just read it, and 
  run what it does by hand.

[books]: https://github.com/BuoyantIO/booksapp
[demo-magic]: https://github.com/paxtonhare/demo-magic/blob/master/demo-magic.sh
[Emissary-ingress]: https://www.getambassador.io/docs/emissary/
[emojivoto]: https://github.com/BuoyantIO/emojivoto
[Linkerd]: https://linkerd.io
