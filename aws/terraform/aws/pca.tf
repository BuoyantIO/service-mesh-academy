# ============================================================
# AWS Private CA — Trust Anchor (Root CA)
# ============================================================

resource "aws_acmpca_certificate_authority" "root" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "EC_prime256v1"
    signing_algorithm = "SHA256WITHECDSA"

    subject {
      common_name = "root.linkerd.cluster.local"
    }
  }

  tags = {
    Name = "${var.project_suffix}-linkerd-root-ca"
  }
}

resource "aws_acmpca_certificate" "root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  signing_algorithm           = "SHA256WITHECDSA"
  template_arn                = "arn:aws:acm-pca:::template/RootCACertificate/V1"
  certificate_signing_request = aws_acmpca_certificate_authority.root.certificate_signing_request

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn
  certificate              = aws_acmpca_certificate.root.certificate
  certificate_chain        = aws_acmpca_certificate.root.certificate_chain
}

# ============================================================
# AWS Private CA — Issuer (Subordinate CA)
# ============================================================

resource "aws_acmpca_certificate_authority" "issuer" {
  type = "SUBORDINATE"

  certificate_authority_configuration {
    key_algorithm     = "EC_prime256v1"
    signing_algorithm = "SHA256WITHECDSA"

    subject {
      common_name = "identity.linkerd.cluster.local"
    }
  }

  tags = {
    Name = "${var.project_suffix}-linkerd-issuer-ca"
  }
}

resource "aws_acmpca_certificate" "issuer" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  signing_algorithm           = "SHA256WITHECDSA"
  template_arn                = "arn:aws:acm-pca:::template/SubordinateCACertificate_PathLen1/V1"
  certificate_signing_request = aws_acmpca_certificate_authority.issuer.certificate_signing_request

  validity {
    type  = "YEARS"
    value = 3
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.root]
}

resource "aws_acmpca_certificate_authority_certificate" "issuer" {
  certificate_authority_arn = aws_acmpca_certificate_authority.issuer.arn
  certificate              = aws_acmpca_certificate.issuer.certificate
  certificate_chain        = aws_acmpca_certificate.issuer.certificate_chain
}
