# Homework assignment

For those of you that want to put in practice some of the theory we covered in
the workshop, you can attempt to re-do parts of the demo, with your own
certificates. This should teach you a bit more about the interaction between
Linkerd and certificates.

**Background**: when installing Linkerd through the CLI, it generates its own
CA and issuer certificate that will bootstrap identity for Linkerd's proxies.
If you want to install through Helm, integrate with your own certificate
management system, or have more control over certificate rotations, then you
need to do things differently. For this **assignment**, the goal is to install
Linkerd with the CLI but with your own self-signed CA and issuer. By the end,
you should feel a bit more comfortable with creating and inspecting
certificates, and operating Linkerd.

**Prerequisites**: you should have the Linkerd CLI installed and a working cluster (e.g k3d, kind, etc.). To generate and inspect certificates, you can use:

- [openssl](https://linux.die.net/man/1/openssl): should come installed with
  your OS in most cases. A bit harder to use because it has many options.
- [step-cli](https://smallstep.com/cli/): lighter tool, a swiss-army knife for
  all of your cryptographic and identity needs. It is my personal
  recommendation since it's easier to understand and use.

**Tasks**:

- [ ] Generate a root CA and its private key. Hint: Root CA should be self
  signed.
- [ ] Generate an issuer, signed by the root CA.
- [ ] Inspect both certificates. Can you find out who signed them (i.e who
  their issuer is). Can you figure out who the certificate is for (i.e the
  subject). What about the public keys? Are they in the certificate, and if so,
  are they easy to pull out?
- [ ] Install Linkerd with your own certificates. Can you find the secret where
  the trust bundle is stored? How is this secret different to the certificates
  Linkerd generates for you?
- [ ] Deploy an example application, verify if it's TLS'd.

- [ ] **Bonus**: post some pictures of your work on Slack or Twitter and tag
  us! Show us if you were successful! :) 
