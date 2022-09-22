Rotating expired certificates
=============================

**NOTE: ANYTIME YOU HAVE EXPIRED CERTIFICATES, YOU WILL TAKE DOWNTIME.**

There's simply no way to avoid downtime when one of Linkerd's certificates
expires: the _moment_ any of the certificates expires, the trust chain
becomes invalid, and things will break as soon as a new workload certificate
gets generated. The moral of the story is **never let these certificates
expire**: rotate them before that.

A good rule of thumb is to rotate halfway through the lifespan of the
certificate. For example, if the certificate will expire in two months,
rotate after a month. If it'll expire in two hours, rotate after one hour.
That gives you plenty of lead time to manage rotation issues.

Managing an Expired Issuer Certificate
--------------------------------------

This is the easy case. If your trust anchor is still valid, but an issuer
has expired, just:

1. Generate a new issuer certificate.
2. Rotate in the new issuer certificate.
3. Restart all your meshed workloads.

You'll still take downtime, but not _much_ downtime.

Managing an Expired Trust Anchor Certificate
--------------------------------------------

This is the more annoying case. You'll need to:

1. Generate a new trust anchor.
2. Rotate in the new trust anchor.
   - Don't bother with bundling the new trust anchor and the old one:
     just replace the old one. It's already expired, so having it in a
     bundle with the new one will do you no good.
3. Generate a new issuer certificate.
4. Rotate that in as well.
5. Restart all your meshed workloads.

It should be clear that the best way to tackle this situation is make sure it
never happens in the first place! Automating certificate rotation is most
definitely the easiest way to go.
