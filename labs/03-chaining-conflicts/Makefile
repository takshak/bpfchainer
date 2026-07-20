.PHONY: verify clean

SCENARIOS := \
	scenario-a-connect4-return-folding \
	scenario-b-shared-map-clobbering \
	scenario-c-sockops-reply-ordering

verify:
	@for scenario in $(SCENARIOS); do \
		echo "==> $$scenario"; \
		$(MAKE) -C $$scenario verify; \
	done

clean:
	@for scenario in $(SCENARIOS); do \
		$(MAKE) -C $$scenario clean; \
	done
