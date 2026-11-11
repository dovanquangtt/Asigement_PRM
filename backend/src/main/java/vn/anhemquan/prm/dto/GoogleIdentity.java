package vn.anhemquan.prm.dto;

/** Verified Google account: {@code subject} is the stable Google user id ("sub" claim). */
public record GoogleIdentity(String subject, String email) {
}
