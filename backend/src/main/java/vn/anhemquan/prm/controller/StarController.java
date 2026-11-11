package vn.anhemquan.prm.controller;

import vn.anhemquan.prm.service.StarService;

import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/stars")
public class StarController {

    private final StarService stars;

    public StarController(StarService stars) {
        this.stars = stars;
    }

    @GetMapping
    public List<Map<String, Object>> list() {
        return stars.stars();
    }
}
