BUILD_DIR := build
ASSETS_DIR := $(BUILD_DIR)/installation-assets
IMAGE_ASSETS := Dockerfile jobqueue.py requirements.txt
KUSTOMIZE_ASSETS := kustomization.yml namespace.yml deployment.yml

.PHONY: all

all: $(BUILD_DIR)/installation-assets.tar.gz $(BUILD_DIR)/uninstall.sh

$(ASSETS_DIR)/image/%: % | $(ASSETS_DIR)
	@-mkdir -p $(dir $@) 2>/dev/null
	cp $< $@

$(ASSETS_DIR)/%: % | $(ASSETS_DIR)
	cp $< $@
	
$(BUILD_DIR)/installation-assets.tar.gz: $(patsubst %,$(ASSETS_DIR)/image/%,$(IMAGE_ASSETS)) $(patsubst %,$(ASSETS_DIR)/%,$(KUSTOMIZE_ASSETS)) 
	cd $(BUILD_DIR) && \
	tar -czvf $(notdir $@) installation-assets

$(BUILD_DIR)/uninstall.sh: uninstall.sh | $(BUILD_DIR)
	cp $< $@

$(BUILD_DIR): ; @-mkdir $@ 2>/dev/null
$(ASSETS_DIR): | $(BUILD_DIR) ; @-mkdir $@ 2>/dev/null
