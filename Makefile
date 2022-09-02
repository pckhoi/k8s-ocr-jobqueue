BUILD_DIR := build
ASSETS_DIR := $(BUILD_DIR)/installation-assets
IMAGE_ASSETS := Dockerfile ocr.py requirements.txt
OTHER_ASSETS := kustomization.yml job.yml uninstall.sh queue_pdf_for_ocr.py

.PHONY: all clean

all: $(BUILD_DIR)/installation-assets.tar.gz

clean:
	rm -rf $(BUILD_DIR)

$(ASSETS_DIR)/image/%: % | $(ASSETS_DIR)
	@-mkdir -p $(dir $@) 2>/dev/null
	cp $< $@

$(ASSETS_DIR)/%: % | $(ASSETS_DIR)
	cp $< $@
	
$(BUILD_DIR)/installation-assets.tar.gz: $(patsubst %,$(ASSETS_DIR)/image/%,$(IMAGE_ASSETS)) $(patsubst %,$(ASSETS_DIR)/%,$(OTHER_ASSETS)) 
	cd $(BUILD_DIR) && \
	tar -czvf $(notdir $@) installation-assets

$(BUILD_DIR): ; @-mkdir $@ 2>/dev/null
$(ASSETS_DIR): | $(BUILD_DIR) ; @-mkdir $@ 2>/dev/null
