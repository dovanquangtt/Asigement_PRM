package vn.anhemquan.prm.stars;

import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/stars")
public class StarController {

    private final StarService stars;

    public StarController(StarService stars) {
        this.stars = stars;
    }

    public record AwardRequest(long employeeId, int delta, String reason) {
    }

    @GetMapping
    public List<Map<String, Object>> list() {
        return stars.stars();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public void award(@RequestBody AwardRequest r) {
        stars.awardStars(r.employeeId(), r.delta(), r.reason());
    }
}
