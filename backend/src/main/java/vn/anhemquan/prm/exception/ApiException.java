package vn.anhemquan.prm.exception;

import org.springframework.http.HttpStatus;

/**
 * Business-rule failure. The message is shown to end users as-is (Vietnamese); {@code code} is the machine
 * readable error code of the app contract (defaults from the HTTP status).
 */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public ApiException(HttpStatus status, String message) {
        this(status, defaultCode(status), message);
    }

    public ApiException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static ApiException badRequest(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, message);
    }

    public static ApiException forbidden(String message) {
        return new ApiException(HttpStatus.FORBIDDEN, message);
    }

    public static ApiException notFound(String message) {
        return new ApiException(HttpStatus.NOT_FOUND, message);
    }

    public static ApiException conflict(String message) {
        return new ApiException(HttpStatus.CONFLICT, message);
    }

    public static ApiException unauthorized(String message) {
        return new ApiException(HttpStatus.UNAUTHORIZED, message);
    }

    /** Same HTTP status family but with a specific machine code, e.g. {@code NO_SHIFT}. */
    public static ApiException of(HttpStatus status, String code, String message) {
        return new ApiException(status, code, message);
    }

    public static String defaultCode(HttpStatus status) {
        return switch (status) {
            case BAD_REQUEST -> "BUSINESS_RULE";
            case UNAUTHORIZED -> "UNAUTHORIZED";
            case FORBIDDEN -> "FORBIDDEN";
            case NOT_FOUND -> "NOT_FOUND";
            case CONFLICT -> "CONFLICT";
            case SERVICE_UNAVAILABLE -> "SERVICE_UNAVAILABLE";
            default -> status.is5xxServerError() ? "INTERNAL_ERROR" : "BUSINESS_RULE";
        };
    }

    public HttpStatus status() {
        return status;
    }

    public String code() {
        return code;
    }
}
