package vn.anhemquan.prm.service;

import vn.anhemquan.prm.dto.GoogleIdentity;

/** Verifies a Google ID token and returns the identity it proves. */
public interface GoogleTokenVerifier {

    /**
     * @throws vn.anhemquan.prm.exception.ApiException 401 for an invalid/expired token or unverified e-mail,
     *                                              503 when Google sign-in is not configured
     */
    GoogleIdentity verify(String idToken);
}
