package vn.anhemquan.prm.service;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import org.springframework.stereotype.Component;

/** Server clock for attendance (second precision, like the SQLite text timestamps). Replaceable in tests. */
@Component
public class AttendanceClock {

    public Instant now() {
        return Instant.now().truncatedTo(ChronoUnit.SECONDS);
    }
}
